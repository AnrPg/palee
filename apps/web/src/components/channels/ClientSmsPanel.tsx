"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { lookupChannelContact, recordStaffConsent, saveChannelContact, type ChannelContact, type ChannelPurpose } from "@/api/channels";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";

import { consentGranted, inputStyle } from "./sms";

const contactKey = (userId: string) => ["admin", "channels", "contact", userId] as const;

/**
 * Πελάτες › καρτέλα › «Κινητό για μηνύματα» (W3 screen 2, option C;
 * ADR-350): staff see the number with only its last three digits, each
 * consent with where it came from, and record what the client told them at
 * the desk — after reading the consent sentence aloud — as source «staff»,
 * with their name and the time. Staff never switch a consent on silently.
 */
export function ClientSmsPanel({ userId }: { userId: string }) {
  const t = useTranslations("Sms");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: contactKey(userId), queryFn: () => lookupChannelContact(token!, userId), enabled: Boolean(token) });
  const [phone, setPhone] = useState("");
  const [asking, setAsking] = useState<ChannelPurpose | null>(null);
  const [said, setSaid] = useState(false);
  const setContact = (contact: ChannelContact | null) => queryClient.setQueryData(contactKey(userId), { contact });

  const savePhone = useMutation({
    mutationFn: () => saveChannelContact(token!, userId, phone.trim()),
    onSuccess: ({ contact }) => {
      setContact(contact);
      setPhone("");
    },
  });
  const record = useMutation({
    mutationFn: ({ contactId, purpose, granted }: { contactId: string; purpose: ChannelPurpose; granted: boolean }) => recordStaffConsent(token!, contactId, purpose, granted),
    onSuccess: ({ contact }) => {
      setContact(contact);
      setAsking(null);
      setSaid(false);
    },
  });

  if (!token || query.isLoading) return null;
  const contact = query.data?.contact ?? null;
  const phoneInvalid = savePhone.error instanceof ApiError && Boolean(savePhone.error.payload.errors?.phone);

  const sourceLine = (purpose: ChannelPurpose) => {
    const consent = contact?.consents.find((entry) => entry.channel === "sms" && entry.purpose === purpose);
    if (!consent) return t("consentNever");
    const at = consent.granted ? consent.granted_at : consent.withdrawn_at;
    const source =
      consent.source === "staff"
        ? t("sourceStaff")
        : consent.source === "stop_keyword"
          ? t("sourceStop")
          : consent.source === "unsubscribe_link"
            ? t("sourceLink")
            : t("sourcePerson");
    return at ? `${source} · ${new Date(at).toLocaleDateString(locale)}` : source;
  };

  return (
    <div className="space-y-3" data-testid="client-sms">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("mobile")}</p>
      {contact ? (
        <p className="font-mono text-sm tabular-nums" style={{ color: "var(--text)" }}>{contact.phone}{contact.opted_out_at ? ` · ${t("stoppedShort")}` : ""}</p>
      ) : null}
      <div className="flex gap-2">
        <input
          type="tel"
          inputMode="tel"
          aria-label={t("mobile")}
          value={phone}
          placeholder={contact ? t("replacePhone") : "+30 69…"}
          aria-invalid={phoneInvalid}
          onChange={(event) => setPhone(event.target.value)}
          className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm"
          style={inputStyle(phoneInvalid)}
        />
        {phone.trim() ? (
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} disabled={savePhone.isPending} onClick={() => savePhone.mutate()}>
            {t("savePhone")}
          </button>
        ) : null}
      </div>
      {phoneInvalid ? <p className="text-xs" style={{ color: "var(--danger-strong)" }}>{t("phoneInvalid")}</p> : null}

      {contact ? (
        <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
          {(["service", "marketing"] as const).map((purpose) => {
            const granted = consentGranted(contact, purpose);
            return (
              <li key={purpose} className="flex flex-wrap items-center gap-3 py-2">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`purpose_${purpose}`)}</p>
                  <p className="text-xs" style={{ color: "var(--dim)" }}>{sourceLine(purpose)}</p>
                </div>
                {granted ? (
                  <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--success) 14%, transparent)", color: "var(--success)" }}>{t("yes")}</span>
                ) : null}
                <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setAsking(purpose)}>
                  {granted ? t("saidStop") : t("saidAtDesk")}
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}

      {asking && contact ? (
        <Dialog
          variant="center"
          size="sm"
          title={consentGranted(contact, asking) ? t("saidStop") : t("saidAtDesk")}
          onClose={() => setAsking(null)}
          dismissible={!record.isPending}
          footer={
            <div className="flex flex-wrap justify-end gap-2">
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setAsking(null)}>{t("cancel")}</button>
              <button
                type="button"
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                disabled={record.isPending || (!consentGranted(contact, asking) && !said)}
                onClick={() => record.mutate({ contactId: contact.id, purpose: asking, granted: !consentGranted(contact, asking) })}
              >
                {t("record")}
              </button>
            </div>
          }
        >
          {consentGranted(contact, asking) ? (
            <p className="text-sm" style={{ color: "var(--text)" }}>{t("stopBody")}</p>
          ) : (
            <div className="space-y-3">
              <p className="rounded-xl p-3 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
                {t("readAloud")} <b>«{t(`readAloud_${asking}`)}»</b>
              </p>
              <label className="flex items-start gap-2 text-sm" style={{ color: "var(--text)" }}>
                <input type="checkbox" checked={said} onChange={(event) => setSaid(event.target.checked)} className="mt-1" />
                <span>
                  <b>{t("clientSaidYes")}</b>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("recordedAs")}</span>
                </span>
              </label>
            </div>
          )}
          {record.isError ? <p className="mt-2 text-xs" style={{ color: "var(--danger-strong)" }}>{t("errors.generic")}</p> : null}
        </Dialog>
      ) : null}
    </div>
  );
}
