"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchChannelMessages, fetchChannelUsage, type ChannelMessage } from "@/api/channels";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationTimeZone } from "@/lib/organization-slug";

import { useSmsError } from "./SmsConnectionSettings";
import { budgetState, deliveryCounts, formatCents, monthLabel, recentMonths, spendParts, type SpendSource } from "./sms";

const SOURCE_COLOR: Record<SpendSource, string> = {
  automation: "var(--series-1)",
  staff: "var(--series-4)",
  system: "var(--series-6)",
};

/**
 * Στατιστικά & Μάρκετινγκ › Μηνύματα SMS (W3 screen 3, option A): the
 * month's cost against the limit as one bar, split by who sent (automatic
 * messages, staff, the system), how many arrived and how many did not, and
 * the latest messages with their state. Months are the box's.
 */
export function SmsCostTab({ token }: { token: string }) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const smsError = useSmsError();
  const zone = useOrganizationTimeZone();
  const months = recentMonths(new Date(), zone, 3);
  const [month, setMonth] = useState(months[0]);
  const usage = useQuery({ queryKey: ["admin", "channels", "usage", month], queryFn: () => fetchChannelUsage(token, month) });
  const latest = useQuery({ queryKey: ["admin", "channels", "messages", "latest"], queryFn: () => fetchChannelMessages(token, { limit: 10 }) });

  const data = usage.data;
  const counts = deliveryCounts(data?.by_status);
  const cap = data?.cap_cents ?? 0;
  const money = (cents: number) => formatCents(cents, data?.currency ?? "EUR", locale);

  return (
    <div className="space-y-4" data-testid="sms-cost">
      <div className="flex flex-wrap items-center gap-3">
        <h2 className="min-w-0 flex-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{t("costTitle", { month: monthLabel(month, locale) })}</h2>
        <Select aria-label={t("month")} value={month} onValueChange={(value: string) => setMonth(value)} className="min-w-[10rem]">
          {months.map((entry) => <option key={entry} value={entry}>{monthLabel(entry, locale)}</option>)}
        </Select>
      </div>

      {usage.isError ? <ErrorNotice>{smsError(usage.error)}</ErrorNotice> : null}
      {usage.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}

      {data ? (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Kpi value={money(data.spent_cents)} label={cap ? t("ofCap", { cap: money(cap) }) : t("noCap")} />
            <Kpi value={String(data.messages)} label={t("messagesParts", { count: data.messages, parts: data.segments ?? data.messages })} />
            <Kpi value={String(counts.delivered)} label={t("deliveredCount", { count: counts.delivered })} />
            <Kpi value={String(counts.failed)} label={t("failedCount", { count: counts.failed })} warn={counts.failed > 0} />
          </div>

          <section className="space-y-3 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex h-3 overflow-hidden rounded-full" style={{ background: "var(--border)" }} role="img" aria-label={t("spentOfCap", { spent: money(data.spent_cents), cap: money(cap) })}>
              {spendParts(data).map((part) => (
                <span key={part.source} className="h-full" style={{ width: `${part.percent}%`, background: SOURCE_COLOR[part.source] }} />
              ))}
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              {spendParts(data).map((part) => (
                <span key={part.source} className="inline-flex items-center gap-2 rounded-full px-3 py-1" style={{ border: "1px solid var(--border)", color: "var(--text)" }} data-testid={`sms-source-${part.source}`}>
                  <span aria-hidden="true" className="h-2.5 w-2.5 rounded-full" style={{ background: SOURCE_COLOR[part.source] }} />
                  {t(`source_${part.source}`)} {money(part.cents)}
                </span>
              ))}
              <span className="min-w-0 flex-1 text-end text-xs" style={{ color: budgetState(data.spent_cents, cap) === "ok" ? "var(--dim)" : "var(--warning)" }}>
                {t("capRule")}
              </span>
            </div>
          </section>
        </>
      ) : null}

      <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <h3 className="font-semibold" style={{ color: "var(--text)" }}>{t("latest")}</h3>
        {latest.data && latest.data.messages.length === 0 ? <p className="mt-2 text-sm" style={{ color: "var(--dim)" }}>{t("noMessages")}</p> : null}
        <ul className="mt-2 divide-y" style={{ borderColor: "var(--border)" }}>
          {(latest.data?.messages ?? []).map((message) => (
            <LatestRow key={message.id} message={message} />
          ))}
        </ul>
      </section>
    </div>
  );
}

function Kpi({ value, label, warn = false }: { value: string; label: string; warn?: boolean }) {
  return (
    <div className="rounded-[1.5rem] p-5" style={{ background: "var(--panel)", border: `1px solid ${warn ? "var(--warning)" : "var(--border)"}` }}>
      <p className="font-mono text-2xl font-bold tabular-nums" style={{ color: warn ? "var(--warning)" : "var(--text)" }}>{value}</p>
      <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{label}</p>
    </div>
  );
}

function LatestRow({ message }: { message: ChannelMessage }) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const when = message.inserted_at
    ? new Date(message.inserted_at).toLocaleString(locale, { timeZone: zone || undefined, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    : "";
  const held = message.status === "queued" && message.hold_reason === "quiet_hours";
  const tone = message.status === "failed" ? "var(--danger-strong)" : message.status === "delivered" || message.status === "sent" ? "var(--success)" : "var(--warning)";
  return (
    <li className="grid grid-cols-[5.5rem_minmax(0,1fr)_auto] items-center gap-3 py-2 text-sm">
      <span className="font-mono text-xs tabular-nums" style={{ color: "var(--dim)" }}>{when}</span>
      <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{message.body} · {message.to}</span>
      <span className="text-xs font-semibold" style={{ color: tone }}>
        {held ? t("status_held") : t(`status_${message.status}`)}
        {message.estimated_cost_cents != null ? ` · ${formatCents(message.cost_cents ?? message.estimated_cost_cents, message.currency ?? "EUR", locale)}` : ""}
      </span>
    </li>
  );
}
