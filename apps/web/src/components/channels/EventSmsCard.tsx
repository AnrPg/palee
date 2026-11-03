"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { eventSmsKey, fetchEventSms } from "@/api/events";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { formatCents } from "./sms";

/**
 * W3 screen 6, options B and C (ADR-385): inside an event the organiser
 * sees «12 από 40 θα πάρουν SMS», what this event's SMS cost so far, and one
 * switch for SMS on this event. The texts stay in Ρυθμίσεις › Μηνύματα SMS.
 * Nothing shows while the organiser sends no SMS and the switch is on.
 */
export function EventSmsCard({ eventId, onSwitch }: { eventId: string; onSwitch: (enabled: boolean) => Promise<unknown> }) {
  const t = useTranslations("Sms");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const summary = useQuery({ queryKey: eventSmsKey(eventId), queryFn: () => fetchEventSms(token!, eventId), enabled: Boolean(token) });
  const toggle = useMutation({
    mutationFn: (enabled: boolean) => onSwitch(enabled),
    onSettled: () => queryClient.invalidateQueries({ queryKey: eventSmsKey(eventId) }),
  });
  const data = summary.data;
  if (!data || (!data.connected && data.enabled)) return null;
  const money = (cents: number) => formatCents(cents, data.currency, locale);

  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="event-sms">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("eventSmsTitle")}</h2>
          <p className="mt-2 text-lg font-bold" style={{ color: "var(--text)" }} data-testid="event-sms-count">
            {data.enabled ? t("eventRecipients", { count: data.recipients, going: data.going }) : t("eventSmsOff")}
          </p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {data.enabled ? t("eventSmsRest") : t("eventSmsOffHint")}
          </p>
        </div>
        <Toggle label={t("eventSmsSwitch")} checked={data.enabled} disabled={toggle.isPending} onChange={(enabled) => toggle.mutate(enabled)} />
      </div>
      <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="event-sms-cost">
        {t("eventCost", { spent: money(data.spent_cents), each: money(data.per_message_cents) })}
      </p>
      {!data.connected ? <p className="text-xs" style={{ color: "var(--warning)" }}>{t("errors.channels_not_connected")}</p> : null}
      {toggle.isError ? <ErrorNotice variant="field">{t("errors.generic")}</ErrorNotice> : null}
    </section>
  );
}
