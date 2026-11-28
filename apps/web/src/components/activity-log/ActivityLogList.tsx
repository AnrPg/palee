"use client";

import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import {
  activityLogKeys,
  exportActivityLog,
  fetchActivityLog,
  type ActivityArea,
  type ActivityLogEntry,
  type ActivityLogFilters,
} from "@/api/activity-log";
import { fetchAdminUsers } from "@/api/admin-users";
import { fetchGymStaff } from "@/api/staff";
import { saveFile } from "@/components/admin/coach-pay/pay-ui";
import { CollapsibleFilterBar } from "@/components/filters/CollapsibleFilterBar";
import { ChoiceChips, FilterSection } from "@/components/filters/FilterPage";
import { useSession } from "@/components/session-provider";
import { Combobox } from "@/components/ui/Combobox";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useDebounced } from "@/hooks/useDebounced";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { clockFormat } from "@/lib/clock";
import { useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

import {
  actorsOf,
  changesOf,
  exportFileName,
  groupByDay,
  mainRole,
  periodOf,
  personName,
  readableAreas,
  relativeDay,
  shownReason,
  type Change,
} from "./activity-log-model";

const ALL = "all";
const ROLE_KEYS = {
  owner: "roleOwner",
  admin: "roleAdmin",
  accountant: "roleAccountant",
  front_desk: "roleFrontDesk",
  coach: "roleCoach",
  janitor: "roleJanitor",
} as const;

export type PickedPerson = { id: string; name: string };

/**
 * ADR-760 (2A): the «Αρχείο ενεργειών» as a timeline by the box's day; a row
 * opens its details (who, when, what changed, why, whether the member sees
 * it). Filters: area (only the reader's), staff member, person, days, text;
 * «Περισσότερα» pages on. With `personId` it is one member's «Ιστορικό».
 */
export function ActivityLogList({
  personId,
  initialPerson = null,
  initialFrom = "",
  initialTo = "",
  initialSensitive = false,
  fullLogHref,
}: {
  /** Fixed to one person (the member profile's «Ιστορικό» tab). */
  personId?: string;
  /** A person filter the page opened with (`?person=`). */
  initialPerson?: PickedPerson | null;
  /** Days and «only sensitive» the page opened with (the owner's daily summary link). */
  initialFrom?: string;
  initialTo?: string;
  initialSensitive?: boolean;
  /** «Όλο το αρχείο →» under a fixed list. */
  fullLogHref?: string;
}) {
  const t = useTranslations("ActivityLog");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const zone = useOrganizationTimeZone();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;

  const [areas, setAreas] = useState<ActivityArea[]>([]);
  const [actorId, setActorId] = useState(ALL);
  const [person, setPerson] = useState<PickedPerson | null>(initialPerson);
  const [personText, setPersonText] = useState("");
  const [from, setFrom] = useState(initialFrom);
  const [to, setTo] = useState(initialTo);
  const [sensitive, setSensitive] = useState(initialSensitive);
  const [text, setText] = useState("");
  const [openId, setOpenId] = useState<string | null>(null);
  const [exportError, setExportError] = useState<unknown>(null);
  const [exporting, setExporting] = useState(false);
  const q = useDebounced(text, 300);
  const fixed = Boolean(personId);

  const filters: ActivityLogFilters = {
    areas: areas.length > 0 ? areas : undefined,
    person_id: personId ?? person?.id,
    actor_id: actorId === ALL ? undefined : actorId,
    from: from || undefined,
    to: to || undefined,
    q: q.trim() || undefined,
    sensitive: sensitive || undefined,
  };

  const log = useInfiniteQuery({
    queryKey: activityLogKeys.list(slug, filters),
    enabled: Boolean(token),
    staleTime: FRESHNESS.live,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam, signal }) => fetchActivityLog(token!, filters, pageParam, signal),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const first = log.data?.pages[0];
  const entries = useMemo(() => (log.data?.pages ?? []).flatMap((page) => page.entries ?? []), [log.data]);
  const offered = readableAreas(first?.areas);

  const staff = useQuery({
    queryKey: [...activityLogKeys.all(slug), "staff"],
    enabled: Boolean(token) && !fixed,
    staleTime: FRESHNESS.reference,
    queryFn: () => fetchGymStaff(token!),
    retry: false,
  });
  const staffOptions = useMemo(() => {
    const named = new Map<string, string>();
    for (const member of staff.data ?? []) if (member.user_id && member.nickname) named.set(member.user_id, member.nickname);
    for (const actor of actorsOf(entries)) if (!named.has(actor.id)) named.set(actor.id, actor.name);
    return [...named.entries()].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name, locale));
  }, [staff.data, entries, locale]);

  const personQuery = useDebounced(personText.trim(), 250);
  const people = useQuery({
    queryKey: [...activityLogKeys.all(slug), "people", personQuery],
    enabled: Boolean(token) && !fixed && personQuery.length >= 2,
    staleTime: FRESHNESS.live,
    queryFn: () => fetchAdminUsers(token!, { q: personQuery, limit: 8 }),
    retry: false,
  });

  const activeCount = (areas.length > 0 ? 1 : 0) + (actorId !== ALL ? 1 : 0) + (person && !fixed ? 1 : 0) + (from || to ? 1 : 0) + (sensitive ? 1 : 0);
  const clear = () => {
    setAreas([]);
    setActorId(ALL);
    setPerson(null);
    setPersonText("");
    setFrom("");
    setTo("");
    setSensitive(false);
  };

  const download = async () => {
    if (!token) return;
    setExporting(true);
    setExportError(null);
    try {
      const blob = await exportActivityLog(token, filters);
      saveFile(blob, exportFileName(new Date()));
    } catch (error) {
      setExportError(error);
    } finally {
      setExporting(false);
    }
  };

  const exportButton = first?.can_export ? (
    <button
      type="button"
      onClick={() => void download()}
      disabled={exporting}
      className="inline-flex min-h-11 shrink-0 items-center rounded-xl px-3 text-sm font-semibold disabled:opacity-60"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
      data-testid="activity-log-export"
    >
      {exporting ? t("exporting") : t("export")}
    </button>
  ) : null;

  const groups = groupByDay(entries, zone);
  const now = new Date();
  const dayTitle = (day: string) => {
    const relative = relativeDay(day, now, zone);
    if (relative) return t(relative);
    return new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(noonUtc(day));
  };
  const clock = clockFormat(locale, { hour: "2-digit", minute: "2-digit", ...(zone ? { timeZone: zone } : {}) });

  return (
    <div className="space-y-4" data-testid="activity-log">
      {fixed ? null : (
        <CollapsibleFilterBar
          ariaLabel={t("filters")}
          search={{ value: text, onChange: setText, placeholder: t("search"), ariaLabel: t("search"), maxLength: 100 }}
          activeCount={activeCount}
          onClear={clear}
          trailing={exportButton}
        >
          {offered.length > 1 ? (
            <FilterSection label={t("area")}>
              <ChoiceChips
                ariaLabel={t("area")}
                multiple
                options={offered.map((area) => ({ value: area, label: t(`areas.${area}`) }))}
                selected={areas}
                onChange={setAreas}
              />
            </FilterSection>
          ) : null}
          <div className="grid gap-3 sm:grid-cols-2">
            <FilterSection label={t("staffMember")}>
              <Select aria-label={t("staffMember")} value={actorId} onValueChange={setActorId} className="min-h-11 w-full rounded-xl px-3 text-sm" data-testid="activity-log-actor">
                <option value={ALL}>{t("anyStaff")}</option>
                {staffOptions.map((option) => (
                  <option key={option.id} value={option.id}>{option.name}</option>
                ))}
              </Select>
            </FilterSection>
            <FilterSection label={t("person")}>
              {person ? (
                <button
                  type="button"
                  onClick={() => setPerson(null)}
                  aria-label={t("clearPerson", { name: person.name })}
                  className="min-h-11 rounded-xl px-3 text-start text-sm font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
                  data-testid="activity-log-person-chip"
                >
                  {person.name} ×
                </button>
              ) : (
                <Combobox
                  value={personText}
                  onValueChange={setPersonText}
                  options={(people.data?.users ?? []).map((user) => ({ id: user.id, label: user.nickname }))}
                  onPick={(option) => {
                    setPerson({ id: option.id, name: option.label });
                    setPersonText("");
                  }}
                  listLabel={t("person")}
                  aria-label={t("person")}
                  placeholder={t("personPlaceholder")}
                  className="min-h-11 w-full rounded-xl px-3 text-sm"
                  inputStyle={{ background: "var(--control-bg)", border: "1px solid var(--control-border)", color: "var(--text)" }}
                />
              )}
            </FilterSection>
            <FilterSection label={t("from")}>
              <DateInput aria-label={t("from")} value={from} max={to || undefined} onValueChange={setFrom} className="min-h-11 w-full rounded-xl px-3 text-sm" />
            </FilterSection>
            <FilterSection label={t("to")}>
              <DateInput aria-label={t("to")} value={to} min={from || undefined} onValueChange={setTo} className="min-h-11 w-full rounded-xl px-3 text-sm" />
            </FilterSection>
          </div>
        </CollapsibleFilterBar>
      )}

      {sensitive && !fixed ? (
        <button
          type="button"
          onClick={() => setSensitive(false)}
          aria-label={t("clearSensitiveOnly")}
          className="min-h-11 rounded-xl px-3 text-start text-sm font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
          data-testid="activity-log-sensitive-chip"
        >
          {t("sensitiveOnly")} ×
        </button>
      ) : null}

      {fixed && exportButton ? <div className="flex justify-end">{exportButton}</div> : null}
      {exportError ? <ErrorNotice>{localizeError(exportError, i18n)}</ErrorNotice> : null}
      {log.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {log.isError ? <ErrorNotice>{localizeError(log.error, i18n)}</ErrorNotice> : null}
      {log.isSuccess && entries.length === 0 ? (
        <p className="rounded-2xl px-4 py-6 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }}>
          {activeCount > 0 || q ? t("emptyFiltered") : t("empty")}
        </p>
      ) : null}
      {log.isSuccess && entries.length > 0 ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("count", { count: entries.length })}</p>
      ) : null}

      {groups.map((group) => (
        <section key={group.day} className="space-y-2">
          <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{dayTitle(group.day)}</h3>
          <ul className="overflow-hidden rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            {group.entries.map((entry, index) => (
              <EntryRow
                key={entry.id}
                entry={entry}
                first={index === 0}
                time={clock.format(new Date(entry.occurred_at))}
                open={openId === entry.id}
                onToggle={() => setOpenId((current) => (current === entry.id ? null : entry.id))}
                onPerson={fixed || !entry.person || entry.redacted ? undefined : () => setPerson({ id: entry.person!.id, name: entry.person!.name ?? t("deletedMember") })}
                onActor={fixed || !entry.actor ? undefined : () => setActorId(entry.actor!.id)}
                zone={zone}
              />
            ))}
          </ul>
        </section>
      ))}

      {log.hasNextPage ? (
        <button
          type="button"
          onClick={() => void log.fetchNextPage()}
          disabled={log.isFetchingNextPage}
          className="min-h-11 w-full rounded-full px-4 text-sm font-semibold disabled:opacity-60"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="activity-log-more"
        >
          {log.isFetchingNextPage ? t("loading") : t("more")}
        </button>
      ) : null}
      {fullLogHref ? (
        <Link href={fullLogHref} className="inline-block text-sm font-semibold" style={{ color: "var(--primary)" }} data-testid="activity-log-full">
          {t("fullLog")}
        </Link>
      ) : null}
    </div>
  );
}

function EntryRow({
  entry,
  first,
  time,
  open,
  onToggle,
  onPerson,
  onActor,
  zone,
}: {
  entry: ActivityLogEntry;
  first: boolean;
  time: string;
  open: boolean;
  onToggle: () => void;
  onPerson?: () => void;
  onActor?: () => void;
  zone: string | null;
}) {
  const t = useTranslations("ActivityLog");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const actor = entry.actor ? entry.actor.name ?? t("deletedMember") : t("system");
  const role = mainRole(entry.actor?.roles);
  const who = personName(entry, t("deletedMember"));
  const reason = shownReason(entry);
  const target = [who, entry.subject_label].filter(Boolean).join(" · ");
  const changes = changesOf(entry);
  const period = periodOf(entry);
  const panelId = `activity-${entry.id}`;
  const when = clockFormat(locale, { day: "numeric", month: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", ...(zone ? { timeZone: zone } : {}) }).format(new Date(entry.occurred_at));

  return (
    <li style={{ borderTop: first ? "none" : "1px solid var(--border)" }} data-testid="activity-log-entry">
      <button type="button" aria-expanded={open} aria-controls={panelId} onClick={onToggle} className="flex w-full items-start gap-3 px-4 py-3 text-start">
        <span className="w-12 shrink-0 pt-0.5 font-mono text-xs" style={{ color: "var(--dim)" }}>{time}</span>
        <span className="min-w-0 flex-1">
          <span className="block text-sm" style={{ color: "var(--text)" }}>
            <strong>{actor}</strong> · {t(`actions.${entry.action}`)}
          </span>
          {target || reason ? (
            <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
              {[target, reason ? `«${reason}»` : null].filter(Boolean).join(" · ")}
            </span>
          ) : null}
        </span>
        <span className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
          {t(`areas.${entry.area}`)}
        </span>
      </button>
      {open ? (
        <dl id={panelId} className="space-y-2 px-4 pb-4 text-sm" data-testid="activity-log-detail">
          {changes.map((change, index) => (
            <Detail key={`${change.field}-${index}`} label={t("changeLabel")}>
              <ChangeText change={change} />
            </Detail>
          ))}
          {period ? (
            <Detail label={t("period")}>{period.to ? t("periodRange", { from: dayText(locale, period.from), to: dayText(locale, period.to) }) : dayText(locale, period.from)}</Detail>
          ) : null}
          {target ? <Detail label={t("about")}>{target}</Detail> : null}
          <Detail label={t("reason")}>{reason ?? <span style={{ color: "var(--dim)" }}>{t("noReason")}</span>}</Detail>
          <Detail label={t("by")}>{[actor, role ? i18n(ROLE_KEYS[role]) : null, when].filter(Boolean).join(" · ")}</Detail>
          <Detail label={t("memberSaw")}>{entry.reason_shared ? t("yes") : t("no")}</Detail>
          {onPerson || onActor ? (
            <div className="flex flex-wrap gap-3 pt-1">
              {onPerson ? (
                <button type="button" onClick={onPerson} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                  {t("onlyPerson", { name: who ?? "" })}
                </button>
              ) : null}
              {onActor ? (
                <button type="button" onClick={onActor} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                  {t("onlyActor", { name: actor })}
                </button>
              ) : null}
            </div>
          ) : null}
        </dl>
      ) : null}
    </li>
  );
}

function Detail({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid gap-1 sm:grid-cols-[10rem_1fr]">
      <dt className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{label}</dt>
      <dd style={{ color: "var(--text)" }}>{children}</dd>
    </div>
  );
}

/** Midday UTC of an ISO day, so formatting it in UTC never moves it to another day. */
function noonUtc(iso: string) {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(year, (month || 1) - 1, day || 1, 12));
}

function dayText(locale: string, iso: string) {
  const date = noonUtc(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return new Intl.DateTimeFormat(locale, { day: "numeric", month: "numeric", year: "numeric", timeZone: "UTC" }).format(date);
}

/** «Κατάσταση: Ληξιπρόθεσμο → Ενεργό»; codes and dates in words. */
function ChangeText({ change }: { change: Change }) {
  const t = useTranslations("ActivityLog");
  const standing = useTranslations("MemberStanding");
  const locale = useUiLocale();
  const value = (raw: string | null) => {
    if (!raw) return t("none");
    if (change.field === "status" && standing.has(`status_${raw}`)) return standing(`status_${raw}` as "status_active");
    if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return dayText(locale, raw);
    return raw;
  };
  const field = t.has(`fields.${change.field}`) ? t(`fields.${change.field}` as "fields.status") : null;
  return (
    <span>
      {field ? `${field}: ` : null}
      <s style={{ color: "var(--dim)" }}>{value(change.before)}</s> → <strong>{value(change.after)}</strong>
    </span>
  );
}
