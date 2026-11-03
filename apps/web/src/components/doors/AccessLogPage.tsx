"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { accessEventsKey, doorsKey, fetchAccessEvents, fetchDoors, type AccessEvent } from "@/api/doors";
import { PageHeader } from "@/components/PageHeader";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { clockFormat } from "@/lib/clock";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { Pill } from "@/components/staff/staff-ui";

import { LOG_FILTERS, logTone, matchesLogFilter, type LogFilter, type LogTone } from "./doors-model";

const PAGE = 100;
const TONE: Record<LogTone, "success" | "warning" | "danger" | "primary"> = { ok: "success", warn: "warning", bad: "danger", manual: "primary" };
const ALL_DOORS = "all";

/**
 * «Ημερολόγιο εισόδων» (W10 screen 6, option A; ADR-381): a timeline with
 * time, who, what, why and which door, filtered by refusals and faults,
 * staff, or one door. Door events without a person show too. Kept 180 days.
 */
export function AccessLogPage() {
  const t = useTranslations("Doors");
  const slug = useOrganizationSlug();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [filter, setFilter] = useState<LogFilter>("all");
  const [doorId, setDoorId] = useState(ALL_DOORS);
  const [limit, setLimit] = useState(PAGE);
  const doors = useQuery({ queryKey: doorsKey(), queryFn: () => fetchDoors(token!), enabled: Boolean(token) });
  const filters = { door_id: doorId === ALL_DOORS ? undefined : doorId, limit };
  const log = useQuery({ queryKey: accessEventsKey(filters), queryFn: () => fetchAccessEvents(token!, filters), enabled: Boolean(token) });
  const rows = (log.data?.events ?? []).filter((event) => matchesLogFilter(event, filter));
  const clock = clockFormat(locale, { hour: "2-digit", minute: "2-digit" });
  const day = new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short" });

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }} data-testid="access-log">
      <div className="mx-auto max-w-3xl space-y-4">
        <BackLink href={adminHref("/admin/check-in", slug)}>{t("backToDesk")}</BackLink>
        <PageHeader title={t("logTitle")} />
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("logKept", { days: 180 })}</p>
        <div className="flex flex-wrap items-center gap-2">
          <SegmentPicker
            ariaLabel={t("logTitle")}
            semantics="radiogroup"
            options={LOG_FILTERS.map((value) => ({ value, label: t(`logFilter.${value}`) }))}
            value={filter}
            onChange={setFilter}
          />
          {(doors.data?.length ?? 0) > 1 ? (
            <Select aria-label={t("logDoor")} value={doorId} onValueChange={(value: string) => setDoorId(value)} className="min-w-[12rem]">
              <option value={ALL_DOORS}>{t("logAllDoors")}</option>
              {(doors.data ?? []).map((door) => <option key={door.id} value={door.id}>{door.name}</option>)}
            </Select>
          ) : null}
        </div>
        {log.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {log.isError ? <ErrorNotice>{t("errors.generic")}</ErrorNotice> : null}
        {log.isSuccess && rows.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("logEmpty")}</p> : null}
        <ul className="divide-y rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)", borderColor: "var(--border)" }}>
          {rows.map((event) => (
            <li key={event.id} className="flex items-start gap-3 px-4 py-3" style={{ borderColor: "var(--border)" }} data-testid="access-row">
              <span className="w-16 shrink-0 font-mono text-xs" style={{ color: "var(--dim)" }}>
                {clock.format(new Date(event.occurred_at))}
                <span className="block font-sans">{day.format(new Date(event.occurred_at))}</span>
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{headline(event, t)}</span>
                <span className="block text-xs" style={{ color: "var(--dim)" }}>{[why(event, t), event.door_name].filter(Boolean).join(" · ")}</span>
              </span>
              <Pill tone={TONE[logTone(event.kind)]}>{t(`kind.${event.kind}`)}</Pill>
            </li>
          ))}
        </ul>
        {log.data && log.data.total > limit ? (
          <button type="button" className="min-h-10 rounded-full px-4 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }} onClick={() => setLimit((value) => Math.min(value + PAGE, 200))} disabled={limit >= 200}>
            {t("logMore")}
          </button>
        ) : null}
      </div>
    </main>
  );
}

type Translate = (key: string, values?: Record<string, string | number>) => string;

/** «Μαρία Παπαδοπούλου · Μπήκε», «Ελένη · Άνοιξε από την υποδοχή», «Η πόρτα δεν απάντησε». */
export function headline(event: AccessEvent, t: Translate) {
  switch (event.kind) {
    case "staff_unlock":
      return t("line.staff_unlock", { name: event.actor_name ?? t("someone") });
    case "door_event":
      return t("line.door_event");
    case "unlock_failed":
      return event.person_name ? t("line.unlock_failed_person", { name: event.person_name }) : t("line.unlock_failed");
    default:
      return t(`line.${event.kind}`, { name: event.person_name ?? t("someone") });
  }
}

function why(event: AccessEvent, t: Translate) {
  const method = t(`method.${event.method}`);
  if (event.kind === "denied" && event.reason) return [t(`reason.${knownReason(event.reason)}`), method].join(" · ");
  if (event.kind === "door_event") return event.provider_event ?? method;
  return method;
}

function knownReason(reason: string) {
  return ["not_a_member", "outside_hours", "no_booking_in_window", "staff_only"].includes(reason) ? reason : "generic";
}
