"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useId, useMemo, useRef, useState } from "react";

import {
  fetchStaffProgramme,
  PROGRAMME_REFUND_POLICIES,
  publishProgramme,
  setProgrammeArchived,
  STAFF_PROGRAMMES_KEY,
  staffProgrammeKey,
  updateProgramme,
  type ProgrammeDay,
  type ProgrammeInput,
  type ProgrammeListing,
  type ProgrammeRefundPolicy,
  type StaffProgramme,
} from "@/api/programmes";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { Select } from "@/components/ui/Select";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import {
  addWorkout,
  columnsFor,
  DAYS_PER_WEEK,
  emptyWeeks,
  MAX_WEEKS,
  MAX_WODS_PER_DAY,
  removeWorkout,
  sameDays,
  trimToWeeks,
  weekRows,
} from "@/components/programmes/programme-grid";
import { GOALS, LEVELS, programmeMoney, useProgrammeError, useProgrammeLabels } from "@/components/programmes/programme-ui";

import { StatusPill } from "./ProgrammesConsole";
import { ProgrammeSales } from "./ProgrammeSales";

type Tab = "programme" | "purchases" | "reviews" | "versions";

const AUTOSAVE_MS = 800;

/**
 * One programme (mockup W8 s1 A, s2 A, s7 A): the weeks grid with a WOD
 * from the library on each day or rest, title, level and goal; the draft
 * saves itself. «Δημοσίευση…» asks for the price and where it shows (refund
 * rule and preview days under «Προχωρημένα»). Once published, «Αγορές»,
 * «Κριτικές» and «Εκδόσεις» follow its sales.
 */
export function ProgrammeEditor({ id }: { id: string }) {
  const t = useTranslations("Programmes");
  const token = useSession().tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const [tab, setTab] = useState<Tab>("programme");
  const [publishing, setPublishing] = useState(false);

  const programme = useQuery({
    queryKey: staffProgrammeKey(id),
    enabled: Boolean(token),
    queryFn: () => fetchStaffProgramme(token, id),
  });

  const archive = useMutation({
    mutationFn: (archived: boolean) => setProgrammeArchived(token, id, archived),
    onSuccess: (saved) => {
      queryClient.setQueryData(staffProgrammeKey(id), saved);
      void queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY });
    },
  });

  const back = <BackLink href={adminHref("/admin/programmes", slug)}>{t("title")}</BackLink>;

  if (programme.isLoading) return <Shell>{back}<p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Shell>;
  if (!programme.data) return <Shell>{back}<ErrorNotice>{programme.error ? programmeError(programme.error) : t("loadFailed")}</ErrorNotice></Shell>;

  const data = programme.data;
  const published = data.status !== "draft";
  const tabs: { value: Tab; label: string }[] = [
    { value: "programme", label: t("tab.programme") },
    { value: "purchases", label: t("tab.purchases") },
    { value: "reviews", label: t("tab.reviews") },
    { value: "versions", label: t("tab.versions") },
  ];

  return (
    <Shell>
      {back}
      <header className="flex flex-wrap items-center gap-3">
        <h1 className="min-w-0 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
          {data.title} · {t("weeks", { count: data.draft_weeks })}
        </h1>
        <StatusPill status={data.status} />
        <span className="flex-1" />
        {data.status === "published" && slug ? (
          <Link
            href={`/b/${encodeURIComponent(slug)}/programmes/${encodeURIComponent(data.id)}`}
            className="min-h-11 px-3 text-sm font-semibold leading-[2.75rem]"
            style={{ color: "var(--text-soft)" }}
            data-testid="programme-preview"
          >
            {t("preview")}
          </Link>
        ) : null}
        {data.status !== "archived" ? (
          <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={() => setPublishing(true)} data-testid="programme-publish-open">
            {published ? t("publishNewVersion") : t("publish")}
          </button>
        ) : null}
        <MoreMenu
          label={t("more")}
          items={
            data.status === "published"
              ? [{ label: t("archive"), onSelect: () => archive.mutate(true), tone: "danger", testId: "programme-archive" }]
              : data.status === "archived"
                ? [{ label: t("restore"), onSelect: () => archive.mutate(false), testId: "programme-restore" }]
                : []
          }
        />
      </header>
      {archive.isError ? <ErrorNotice>{programmeError(archive.error)}</ErrorNotice> : null}
      {data.status === "archived" ? <p className="text-sm" style={{ color: "var(--muted)" }}>{t("archivedHint")}</p> : null}

      {published ? (
        <SegmentPicker<Tab> options={tabs} value={tab} onChange={setTab} ariaLabel={data.title} variant="track" />
      ) : null}

      {tab === "programme" || !published ? (
        <Builder key={data.id} programme={data} token={token} />
      ) : (
        <ProgrammeSales programme={data} tab={tab} token={token} />
      )}

      {publishing ? <PublishDialog programme={data} token={token} onClose={() => setPublishing(false)} /> : null}
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return <div className="mx-auto flex w-full max-w-6xl flex-col gap-4 px-4 py-6" data-testid="programme-editor">{children}</div>;
}

// ── Builder (s1 A) ─────────────────────────────────────────────────────────

type Draft = {
  title: string;
  summary: string;
  level: string;
  goal: string;
  weeks: number;
  days: ProgrammeDay[];
};

function draftOf(programme: StaffProgramme): Draft {
  return {
    title: programme.title,
    summary: programme.summary ?? "",
    level: programme.level ?? "all",
    goal: programme.goal ?? "general",
    weeks: programme.draft_weeks,
    days: programme.draft_days ?? [],
  };
}

function changesOf(saved: StaffProgramme, draft: Draft): ProgrammeInput | null {
  const body: ProgrammeInput = {};
  if (draft.title.trim() !== saved.title && draft.title.trim().length >= 2) body.title = draft.title.trim();
  if (draft.summary.trim() !== (saved.summary ?? "")) body.summary = draft.summary.trim() || null;
  if (draft.level !== saved.level) body.level = draft.level as ProgrammeInput["level"];
  if (draft.goal !== saved.goal) body.goal = draft.goal as ProgrammeInput["goal"];
  if (draft.weeks !== saved.draft_weeks) body.draft_weeks = draft.weeks;
  if (draft.weeks !== saved.draft_weeks || !sameDays(draft.days, saved.draft_days ?? [])) body.draft_days = draft.days;
  return Object.keys(body).length > 0 ? body : null;
}

function Builder({ programme, token }: { programme: StaffProgramme; token: string }) {
  const t = useTranslations("Programmes");
  const labels = useProgrammeLabels();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const [draft, setDraft] = useState<Draft>(() => draftOf(programme));
  const [columns, setColumns] = useState(() => columnsFor(programme.draft_days ?? []));
  const [picking, setPicking] = useState<number | null>(null);
  const [savedAt, setSavedAt] = useState<Date | null>(null);
  const saved = useRef(programme);
  const ids = { title: useId(), summary: useId(), level: useId(), goal: useId(), columns: useId() };

  const workouts = useQuery({
    queryKey: ["admin", "workouts"],
    enabled: Boolean(token),
    queryFn: () => listAdminWorkouts(token),
  });
  const published = useMemo(
    () => (Array.isArray(workouts.data) ? workouts.data : []).filter((workout) => workout?.id && workout.status === "published"),
    [workouts.data],
  );
  const titles = useMemo(() => new Map(published.map((workout) => [workout.id, workout.title])), [published]);

  const save = useMutation({
    mutationFn: (body: ProgrammeInput) => updateProgramme(token, programme.id, body),
    onSuccess: (next) => {
      saved.current = next;
      setSavedAt(new Date());
      queryClient.setQueryData(staffProgrammeKey(programme.id), next);
      void queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY, exact: true });
    },
  });
  const { mutate, isPending } = save;

  // The draft saves itself a moment after each change (mockup s1 «Πρόχειρο αποθηκεύεται μόνο του»).
  useEffect(() => {
    if (isPending) return;
    const body = changesOf(saved.current, draft);
    if (!body) return;
    const timer = window.setTimeout(() => mutate(body), AUTOSAVE_MS);
    return () => window.clearTimeout(timer);
  }, [draft, isPending, mutate]);

  const rows = weekRows(draft.weeks, draft.days, columns);
  const set = <K extends keyof Draft>(key: K, value: Draft[K]) => setDraft((current) => ({ ...current, [key]: value }));
  const titleInvalid = draft.title.trim().length < 2;

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
      <section className="min-w-0 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-labelledby={ids.columns}>
        <h2 id={ids.columns} className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("weeksTitle")}</h2>
        <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("gridHint")}</p>
        <div className="mt-3 overflow-x-auto">
          <table className="w-full min-w-[36rem] border-separate border-spacing-1 text-sm" data-testid="programme-grid">
            <thead>
              <tr>
                <th className="w-20" />
                {Array.from({ length: columns }, (_, slot) => (
                  <th key={slot} scope="col" className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("dayShort", { day: slot + 1 })}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.week}>
                  <th scope="row" className="text-start text-xs font-semibold" style={{ color: "var(--text)" }}>{t("weekShort", { week: row.week + 1 })}</th>
                  {row.cells.map((cell) => (
                    <td key={cell.day} className="align-top">
                      <div className="flex min-h-14 flex-col gap-1 rounded-xl p-1.5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                        {cell.workoutIds.length === 0 ? (
                          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("rest")}</span>
                        ) : (
                          cell.workoutIds.map((workoutId) => (
                            <span
                              key={workoutId}
                              className="flex min-w-0 items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold"
                              style={{ background: "color-mix(in srgb, var(--primary) 12%, var(--panel))", color: "var(--text)" }}
                            >
                              <span className="min-w-0 flex-1 truncate">{titles.get(workoutId) ?? t("unknownWod")}</span>
                              <button
                                type="button"
                                aria-label={t("removeWod", { title: titles.get(workoutId) ?? t("unknownWod") })}
                                onClick={() => set("days", removeWorkout(draft.days, cell.day, workoutId))}
                                style={{ color: "var(--muted)" }}
                              >
                                ×
                              </button>
                            </span>
                          ))
                        )}
                        {cell.workoutIds.length < MAX_WODS_PER_DAY ? (
                          <button
                            type="button"
                            onClick={() => setPicking(cell.day)}
                            className="text-start text-xs font-semibold"
                            style={{ color: "var(--primary)" }}
                            data-testid={`programme-add-${cell.day}`}
                          >
                            {t("addWod")}
                          </button>
                        ) : null}
                      </div>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {draft.weeks < MAX_WEEKS ? (
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => set("weeks", draft.weeks + 1)} data-testid="programme-add-week">
              {t("addWeek")}
            </button>
          ) : null}
          {draft.weeks > 1 ? (
            <button
              type="button"
              className={secondaryButtonClass}
              style={secondaryButtonStyle}
              onClick={() => setDraft((current) => ({ ...current, weeks: current.weeks - 1, days: trimToWeeks(current.days, current.weeks - 1) }))}
            >
              {t("removeWeek")}
            </button>
          ) : null}
        </div>
      </section>

      <aside className="flex min-w-0 flex-col gap-3 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <h2 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("detailsCard")}</h2>
        <div>
          <label htmlFor={ids.title} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldTitle")}</label>
          <input
            id={ids.title}
            className={inputClass}
            style={titleInvalid ? { ...inputStyle, borderColor: "var(--danger)" } : inputStyle}
            value={draft.title}
            maxLength={120}
            aria-invalid={titleInvalid}
            onChange={(event) => set("title", event.target.value)}
          />
          {titleInvalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("titleRequired")}</p> : null}
        </div>
        <div>
          <label htmlFor={ids.summary} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldSummary")}</label>
          <textarea id={ids.summary} className={inputClass} style={inputStyle} rows={3} maxLength={600} value={draft.summary} onChange={(event) => set("summary", event.target.value)} />
        </div>
        <div>
          <label htmlFor={ids.level} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldLevel")}</label>
          <Select id={ids.level} className={inputClass} style={inputStyle} value={draft.level} onValueChange={(value) => set("level", value)}>
            {LEVELS.map((level) => <option key={level} value={level}>{labels.level(level)}</option>)}
          </Select>
        </div>
        <div>
          <label htmlFor={ids.goal} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldGoal")}</label>
          <Select id={ids.goal} className={inputClass} style={inputStyle} value={draft.goal} onValueChange={(value) => set("goal", value)}>
            {GOALS.map((goal) => <option key={goal} value={goal}>{labels.goal(goal)}</option>)}
          </Select>
        </div>
        <AdvancedDisclosure count={1}>
          <div>
            <label className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("daysPerWeek")}</label>
            <Select className={inputClass} style={inputStyle} value={columns} onValueChange={(value) => setColumns(columnsFor(draft.days, Number(value)))} aria-label={t("daysPerWeek")}>
              {[5, 6, DAYS_PER_WEEK].map((value) => <option key={value} value={value}>{value}</option>)}
            </Select>
            <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("daysPerWeekHint")}</p>
          </div>
        </AdvancedDisclosure>
        <p className="text-xs" role="status" style={{ color: save.isError ? "var(--danger)" : "var(--dim)" }} data-testid="programme-save-state">
          {save.isError ? programmeError(save.error) : isPending ? t("saving") : savedAt ? t("saved") : t("draftSavesItself")}
        </p>
      </aside>

      {picking !== null ? (
        <WodPicker
          workouts={published}
          loading={workouts.isLoading}
          chosen={draft.days.filter((row) => row.day === picking).map((row) => row.workout_id)}
          onPick={(workoutId) => {
            set("days", addWorkout(draft.days, picking, workoutId));
            setPicking(null);
          }}
          onClose={() => setPicking(null)}
          day={picking}
        />
      ) : null}
    </div>
  );
}

function WodPicker({
  workouts,
  loading,
  chosen,
  day,
  onPick,
  onClose,
}: {
  workouts: WorkoutRecord[];
  loading: boolean;
  chosen: string[];
  day: number;
  onPick: (id: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Programmes");
  const [query, setQuery] = useState("");
  const shown = workouts
    .filter((workout) => !chosen.includes(workout.id))
    .filter((workout) => workout.title.toLowerCase().includes(query.trim().toLowerCase()))
    .slice(0, 50);
  return (
    <Dialog
      onClose={onClose}
      title={t("pickWodTitle", { week: Math.floor(day / DAYS_PER_WEEK) + 1, day: (day % DAYS_PER_WEEK) + 1 })}
      size="md"
      testId="programme-wod-picker"
    >
      <input
        className={inputClass}
        style={inputStyle}
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t("searchWods")}
        aria-label={t("searchWods")}
        autoFocus
      />
      {loading ? <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {!loading && shown.length === 0 ? <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{t("noWods")}</p> : null}
      <ul className="mt-3 flex flex-col">
        {shown.map((workout) => (
          <li key={workout.id}>
            <button
              type="button"
              onClick={() => onPick(workout.id)}
              className="flex min-h-11 w-full items-center gap-2 rounded-xl px-3 text-start text-sm font-semibold"
              style={{ color: "var(--text)" }}
              data-testid={`programme-pick-${workout.id}`}
            >
              {workout.icon ? <span aria-hidden="true">{workout.icon}</span> : null}
              <span className="min-w-0 flex-1 truncate">{workout.title}</span>
            </button>
          </li>
        ))}
      </ul>
    </Dialog>
  );
}

// ── Publish (s2 A) ─────────────────────────────────────────────────────────

function PublishDialog({ programme, token, onClose }: { programme: StaffProgramme; token: string; onClose: () => void }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const priceId = useId();
  const [price, setPrice] = useState(programme.price_cents ? (programme.price_cents / 100).toFixed(2) : "");
  const [listing, setListing] = useState<ProgrammeListing>(programme.listing ?? "box");
  const [previewDays, setPreviewDays] = useState(programme.preview_days ?? 3);
  const [refundPolicy, setRefundPolicy] = useState<ProgrammeRefundPolicy>(programme.refund_policy ?? "before_start");
  const [touched, setTouched] = useState(false);
  const cents = Math.round(Number(price.replace(",", ".")) * 100);
  const priceInvalid = !Number.isFinite(cents) || cents <= 0;
  const empty = emptyWeeks(programme.draft_weeks, programme.draft_days ?? []);
  const nextVersion = (programme.versions?.length ?? (programme.version ? programme.version.number : 0)) + 1;

  const publish = useMutation({
    mutationFn: async () => {
      await updateProgramme(token, programme.id, {
        price_cents: cents,
        listing,
        preview_days: previewDays,
        refund_policy: refundPolicy,
      });
      return publishProgramme(token, programme.id);
    },
    onSuccess: async (saved) => {
      queryClient.setQueryData(staffProgrammeKey(programme.id), saved);
      await queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY });
      onClose();
    },
  });

  const blockers = [
    programme.online_payments === false ? t("blockerPayments") : null,
    (programme.draft_days ?? []).length === 0 ? t("blockerNoWods") : null,
  ].filter(Boolean) as string[];

  return (
    <Dialog
      onClose={onClose}
      title={t("publishTitle", { version: nextVersion })}
      size="md"
      testId="programme-publish"
      onSubmit={() => {
        setTouched(true);
        if (!priceInvalid && blockers.length === 0) publish.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button type="submit" disabled={publish.isPending || blockers.length > 0} className={primaryButtonClass} style={primaryButtonStyle} data-testid="programme-publish">
            {t("publishConfirm")}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {blockers.map((blocker) => <ErrorNotice key={blocker} variant="field">{blocker}</ErrorNotice>)}
        {empty.length > 0 && blockers.length === 0 ? (
          <p className="text-xs" style={{ color: "var(--warning)" }}>{t("emptyWeeksWarning", { count: empty.length, weeks: empty.join(", ") })}</p>
        ) : null}
        <div>
          <label htmlFor={priceId} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("price")}</label>
          <div className="flex items-center gap-2">
            <input
              id={priceId}
              inputMode="decimal"
              className={inputClass}
              style={touched && priceInvalid ? { ...inputStyle, borderColor: "var(--danger)" } : inputStyle}
              value={price}
              aria-invalid={touched && priceInvalid}
              onChange={(event) => setPrice(event.target.value)}
              data-testid="programme-price"
            />
            <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>{t("withVat", { currency: programme.currency || "EUR" })}</span>
          </div>
          {touched && priceInvalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("priceRequired")}</p> : null}
          {!priceInvalid ? <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{programmeMoney(locale, cents, programme.currency)}</p> : null}
        </div>
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("whereShown")}</legend>
          {(["box", "marketplace"] as const).map((value) => (
            <label
              key={value}
              className="flex cursor-pointer items-start gap-3 rounded-2xl p-3"
              style={{ background: "var(--panel-muted)", border: `1px solid ${listing === value ? "var(--primary)" : "var(--border)"}` }}
            >
              <input type="radio" name="listing" checked={listing === value} onChange={() => setListing(value)} className="mt-1" data-testid={`programme-listing-${value}`} />
              <span>
                <b className="block text-sm" style={{ color: "var(--text)" }}>{t(`listing.${value}`)}</b>
                <span className="block text-xs" style={{ color: "var(--muted)" }}>{t(`listingHint.${value}`)}</span>
              </span>
            </label>
          ))}
        </fieldset>
        <AdvancedDisclosure count={2}>
          <div>
            <label className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("previewDays")}</label>
            <Select className={inputClass} style={inputStyle} value={previewDays} onValueChange={(value) => setPreviewDays(Number(value))} aria-label={t("previewDays")}>
              {Array.from({ length: 15 }, (_, n) => <option key={n} value={n}>{n}</option>)}
            </Select>
            <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("previewDaysHint")}</p>
          </div>
          <div>
            <label className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("refundRule")}</label>
            <Select className={inputClass} style={inputStyle} value={refundPolicy} onValueChange={(value) => setRefundPolicy(value as ProgrammeRefundPolicy)} aria-label={t("refundRule")}>
              {PROGRAMME_REFUND_POLICIES.map((policy) => <option key={policy} value={policy}>{t(`refund.${policy}`)}</option>)}
            </Select>
          </div>
        </AdvancedDisclosure>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("freezeNote")}</p>
        {publish.isError ? <ErrorNotice variant="field">{programmeError(publish.error)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
