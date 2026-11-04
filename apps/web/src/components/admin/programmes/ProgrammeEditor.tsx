"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  fetchStaffProgramme,
  setProgrammeArchived,
  STAFF_PROGRAMMES_KEY,
  staffProgrammeKey,
  updateProgramme,
  type ProgrammeInput,
  type StaffProgramme,
} from "@/api/programmes";
import { listAdminWorkouts } from "@/api/workouts";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { useProgrammeError } from "@/components/programmes/programme-ui";

import { useDesktopLayout, useNotice } from "./editor-ui";
import { ProgrammeDetails } from "./ProgrammeDetails";
import { changesOf, draftOf, libraryOf, liveReadiness, type Draft, type ReadinessTarget } from "./programme-editor-model";
import { StatusPill } from "./ProgrammesConsole";
import { ProgrammeSales } from "./ProgrammeSales";
import { PublishDialog } from "./PublishDialog";
import { ReadinessBanner, ReadinessBar } from "./Readiness";
import { WeeksDesktop } from "./WeeksDesktop";
import { WeeksPhone } from "./WeeksPhone";
import type { WeeksChange } from "./WeekActions";

type Tab = "weeks" | "details" | "purchases" | "reviews" | "versions";

const AUTOSAVE_MS = 800;

/**
 * One programme (board 2026-11-04, screens 1κ A and 1μ A). «Εβδομάδες»: on a
 * phone one week at a time with the days as tall rows and the WOD library in
 * a sheet; from `lg` up every week in a grid with the library beside it,
 * drag and drop and keyboard shortcuts. «Στοιχεία»: title, summary, level,
 * goal, cover photo and equipment. The draft saves itself; «Λείπουν N
 * πράγματα» lists what is missing before «Δημοσίευση…». Once published,
 * «Αγορές», «Κριτικές» and «Εκδόσεις» follow its sales.
 */
export function ProgrammeEditor({ id }: { id: string }) {
  const t = useTranslations("Programmes");
  const token = useSession().tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const programmeError = useProgrammeError();

  const programme = useQuery({
    queryKey: staffProgrammeKey(id),
    enabled: Boolean(token),
    queryFn: () => fetchStaffProgramme(token, id),
  });

  const back = <BackLink href={adminHref("/admin/programmes", slug)}>{t("title")}</BackLink>;

  if (programme.isLoading) return <Shell>{back}<p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Shell>;
  if (!programme.data) return <Shell>{back}<ErrorNotice>{programme.error ? programmeError(programme.error) : t("loadFailed")}</ErrorNotice></Shell>;

  return (
    <Shell>
      {back}
      <Editor key={programme.data.id} programme={programme.data} token={token} slug={slug} />
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return <div className="mx-auto flex w-full max-w-7xl flex-col gap-4 px-4 pt-6" data-testid="programme-editor">{children}</div>;
}

function Editor({ programme, token, slug }: { programme: StaffProgramme; token: string; slug: string | null }) {
  const t = useTranslations("Programmes");
  const te = useTranslations("Programmes.editor2");
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const desktop = useDesktopLayout();
  const { notice, say } = useNotice();
  const [draft, setDraft] = useState<Draft>(() => draftOf(programme));
  const [tab, setTab] = useState<Tab>("weeks");
  const [week, setWeek] = useState(0);
  const [jump, setJump] = useState<{ week: number; at: number } | null>(null);
  const [focus, setFocus] = useState<{ field: "title" | "summary"; at: number } | null>(null);
  const [publishing, setPublishing] = useState(false);
  const [savedAt, setSavedAt] = useState<Date | null>(null);
  const saved = useRef(programme);

  const workouts = useQuery({
    queryKey: ["admin", "workouts"],
    enabled: Boolean(token),
    queryFn: () => listAdminWorkouts(token),
  });
  const library = useMemo(() => libraryOf(workouts.data), [workouts.data]);

  const onSaved = useCallback(
    (next: StaffProgramme) => {
      saved.current = next;
      setSavedAt(new Date());
      queryClient.setQueryData(staffProgrammeKey(programme.id), next);
      void queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY, exact: true });
    },
    [programme.id, queryClient],
  );

  const save = useMutation({
    mutationFn: (body: ProgrammeInput) => updateProgramme(token, programme.id, body),
    onSuccess: onSaved,
  });
  const { mutate, isPending } = save;

  // The draft saves itself a moment after each change.
  useEffect(() => {
    if (isPending) return;
    const body = changesOf(saved.current, draft);
    if (!body) return;
    const timer = window.setTimeout(() => mutate(body), AUTOSAVE_MS);
    return () => window.clearTimeout(timer);
  }, [draft, isPending, mutate]);

  // The cover, the derived facts and the status come back on the cached programme, which re-renders this with it.
  const current = programme;

  const archive = useMutation({
    mutationFn: (archived: boolean) => setProgrammeArchived(token, programme.id, archived),
    onSuccess: (next) => {
      saved.current = next;
      queryClient.setQueryData(staffProgrammeKey(programme.id), next);
      void queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY });
    },
  });

  const update = (patch: Partial<Draft>) => setDraft((value) => ({ ...value, ...patch }));
  const changeWeeks = (change: WeeksChange) => setDraft((value) => ({ ...value, ...change }));
  const readiness = liveReadiness(draft);
  const status = current.status;
  const published = status !== "draft";
  const publishLabel = status === "archived" ? null : published ? t("publishNewVersion") : t("publish");

  function go(target: ReadinessTarget) {
    if (target.tab === "details") {
      setTab("details");
      setFocus({ field: target.field, at: Date.now() });
      return;
    }
    setTab("weeks");
    setWeek(target.week);
    setJump({ week: target.week, at: Date.now() });
  }

  async function flush() {
    const body = changesOf(saved.current, draft);
    if (body) onSaved(await updateProgramme(token, programme.id, body));
  }

  const tabs: { value: Tab; label: string }[] = [
    { value: "weeks", label: te("tabWeeks") },
    { value: "details", label: te("tabDetails") },
    ...(published
      ? ([
          { value: "purchases", label: t("tab.purchases") },
          { value: "reviews", label: t("tab.reviews") },
          { value: "versions", label: t("tab.versions") },
        ] as const)
      : []),
  ];

  const saveState = save.isError ? programmeError(save.error) : isPending ? t("saving") : savedAt ? t("saved") : t("draftSavesItself");

  return (
    <>
      <header className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <h1 className="min-w-0 truncate text-xl font-semibold tracking-tight lg:text-2xl" style={{ color: "var(--text)" }}>
          {draft.title.trim() || programme.title}
        </h1>
        <StatusPill status={status} />
        <span
          className="text-xs"
          role="status"
          style={{ color: save.isError ? "var(--danger)" : "var(--dim)" }}
          data-testid="programme-save-state"
        >
          {!save.isError && savedAt && !isPending ? <span aria-hidden="true">✓ </span> : null}
          {saveState}
        </span>
        <span className="flex-1" />
        {status === "published" && slug && desktop ? (
          <Link
            href={`/b/${encodeURIComponent(slug)}/programmes/${encodeURIComponent(programme.id)}`}
            className="min-h-11 px-3 text-sm font-semibold leading-[2.75rem]"
            style={{ color: "var(--text-soft)" }}
            data-testid="programme-preview"
          >
            {t("preview")}
          </Link>
        ) : null}
        {desktop && publishLabel ? (
          <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={() => setPublishing(true)} data-testid="programme-publish-open">
            {publishLabel}
          </button>
        ) : null}
        <MoreMenu
          label={t("more")}
          items={
            status === "published"
              ? [{ label: t("archive"), onSelect: () => archive.mutate(true), tone: "danger", testId: "programme-archive" }]
              : status === "archived"
                ? [{ label: t("restore"), onSelect: () => archive.mutate(false), testId: "programme-restore" }]
                : []
          }
        />
      </header>
      {archive.isError ? <ErrorNotice>{programmeError(archive.error)}</ErrorNotice> : null}
      {status === "archived" ? <p className="text-sm" style={{ color: "var(--muted)" }}>{t("archivedHint")}</p> : null}

      <SegmentPicker<Tab> options={tabs} value={tab} onChange={setTab} ariaLabel={programme.title} variant="track" stretch={!desktop} />

      <p className="sr-only" role="status" aria-live="polite" data-testid="programme-notice">{notice}</p>
      {notice ? (
        <p
          aria-hidden="true"
          className="pointer-events-none fixed inset-x-0 z-(--z-toast) mx-auto w-max max-w-[90vw] rounded-full px-4 py-2 text-sm font-semibold shadow-lg"
          style={{ bottom: desktop ? "2rem" : "calc(var(--bottom-float-inset, 0px) + 5.5rem)", background: "var(--text)", color: "var(--bg)" }}
        >
          {notice}
        </p>
      ) : null}

      <div className="pb-6">
        {tab === "weeks" ? (
          desktop ? (
            <WeeksDesktop
              days={draft.days}
              weeks={draft.weeks}
              library={library}
              loading={workouts.isLoading}
              jump={jump}
              banner={status !== "archived" ? <ReadinessBanner items={readiness} onGo={go} /> : null}
              onChange={changeWeeks}
              say={say}
            />
          ) : (
            <WeeksPhone
              days={draft.days}
              weeks={draft.weeks}
              week={week}
              onWeek={setWeek}
              library={library}
              loading={workouts.isLoading}
              onChange={changeWeeks}
              say={say}
            />
          )
        ) : tab === "details" ? (
          <div className="flex flex-col gap-3">
            {desktop && status !== "archived" ? <ReadinessBanner items={readiness} onGo={go} /> : null}
            <ProgrammeDetails programme={current} draft={draft} token={token} focus={focus} onChange={update} />
          </div>
        ) : (
          <ProgrammeSales programme={current} tab={tab} token={token} />
        )}
      </div>

      {!desktop && (tab === "weeks" || tab === "details") && status !== "archived" ? (
        <ReadinessBar items={readiness} publishLabel={publishLabel} onPublish={() => setPublishing(true)} onGo={go} />
      ) : null}

      {publishing ? <PublishDialog programme={current} token={token} beforePublish={flush} onClose={() => setPublishing(false)} /> : null}
    </>
  );
}
