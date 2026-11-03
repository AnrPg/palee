"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { MEMBER_CONSENT_TEXT, fetchMyChannels, saveMyChannels, type ChannelPurpose, type MyChannels, type MyChannelsUpdate } from "@/api/channels";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { HubCard } from "@/components/member-app/HubParts";
import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { consentGranted, inputStyle, smsLocale } from "./sms";

export { smsLocale };

export const myChannelsKey = (slug: string) => ["me", "channels", slug] as const;

/** The «phone» field's error from the API, in words; null for any other error. */
export function usePhoneError() {
  const t = useTranslations("Sms");
  return (error: unknown): string | null => (error instanceof ApiError && error.payload.errors?.phone ? t("phoneInvalid") : null);
}

/**
 * Box › Ειδοποιήσεις (W3 screen 2, option A; ADR-350): the member's mobile
 * for this box's messages and two separate switches, «Ενημερώσεις με SMS»
 * and «Προσφορές με SMS» (off until they say yes). After STOP the card says
 * so and offers to start updates again. Shown only when the box sends SMS.
 */
export function BoxSmsCard({ membership }: BoxExtensionProps) {
  const t = useTranslations("Sms");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const slug = membership.organization.slug;
  const query = useQuery({ queryKey: myChannelsKey(slug), queryFn: () => fetchMyChannels(token!, slug), enabled: Boolean(token) });
  if (!token || !Array.isArray(query.data?.channels) || !query.data.channels.includes("sms")) return null;
  return (
    <HubCard eyebrow={t("memberEyebrow")}>
      <MySmsForm token={token} slug={slug} boxName={membership.settings?.brand_name?.trim() || membership.organization.name} data={query.data} />
    </HubCard>
  );
}

function MySmsForm({ token, slug, boxName, data }: { token: string; slug: string; boxName: string; data: MyChannels }) {
  const t = useTranslations("Sms");
  const locale = useLocale();
  const phoneError = usePhoneError();
  const queryClient = useQueryClient();
  const contact = data.contact;
  const [phone, setPhone] = useState(contact?.phone ?? "");
  const [needPhone, setNeedPhone] = useState(false);
  const save = useMutation({
    mutationFn: (update: MyChannelsUpdate) => saveMyChannels(token, slug, { locale: smsLocale(locale), text_version: MEMBER_CONSENT_TEXT, ...update }),
    onSuccess: (next) => {
      queryClient.setQueryData(myChannelsKey(slug), next);
      setNeedPhone(false);
    },
  });
  const phoneChanged = phone.trim() !== (contact?.phone ?? "");
  const fieldError = needPhone ? t("phoneFirst") : save.isError ? phoneError(save.error) : null;

  const toggle = (purpose: ChannelPurpose, granted: boolean) => {
    if (!contact && phone.trim() === "") {
      setNeedPhone(true);
      return;
    }
    save.mutate({ ...(phoneChanged || !contact ? { phone: phone.trim() } : {}), consents: [{ channel: "sms", purpose, granted }] });
  };

  return (
    <div className="flex flex-col gap-4" data-testid="my-sms">
      {contact?.opted_out_at ? (
        <div className="rounded-2xl p-4" style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)" }} data-testid="my-sms-stopped">
          <p className="font-semibold" style={{ color: "var(--text)" }}>{t("stoppedTitle")}</p>
          <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
            {t("stoppedBody", { date: new Date(contact.opted_out_at).toLocaleDateString(locale) })}
          </p>
          <button type="button" className="mt-3 rounded-full px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }} disabled={save.isPending} onClick={() => toggle("service", true)}>
            {t("restartUpdates")}
          </button>
        </div>
      ) : null}

      <div>
        <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="my-sms-phone">{t("mobile")}</label>
        <div className="mt-2 flex gap-2">
          <input
            id="my-sms-phone"
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            value={phone}
            placeholder="+30 69…"
            aria-invalid={Boolean(fieldError)}
            aria-describedby={fieldError ? "my-sms-phone-error" : undefined}
            onChange={(event) => setPhone(event.target.value)}
            className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm"
            style={inputStyle(Boolean(fieldError))}
          />
          {phoneChanged && contact ? (
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} disabled={save.isPending} onClick={() => save.mutate({ phone: phone.trim() })}>
              {t("savePhone")}
            </button>
          ) : null}
        </div>
        {fieldError ? <p id="my-sms-phone-error" className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{fieldError}</p> : null}
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("mobileHint", { box: boxName })}</p>
      </div>

      <div className="divide-y" style={{ borderColor: "var(--border)" }}>
        {(["service", "marketing"] as const).map((purpose) => (
          <div key={purpose} className="flex items-center gap-3 py-3">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`purpose_${purpose}`)}</p>
              <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t(`purpose_${purpose}_hint`)}</p>
            </div>
            <Toggle label={t(`purpose_${purpose}`)} checked={consentGranted(contact, purpose)} disabled={save.isPending} onChange={(granted) => toggle(purpose, granted)} />
          </div>
        ))}
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("memberFooter")}</p>
      {save.isError && !fieldError ? <ErrorNotice variant="field">{t("errors.generic")}</ErrorNotice> : null}
    </div>
  );
}
