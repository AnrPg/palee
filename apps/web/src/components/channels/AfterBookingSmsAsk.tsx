"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { BOOKING_CONSENT_TEXT, fetchMyChannels, saveMyChannels } from "@/api/channels";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";

import { myChannelsKey, smsLocale, usePhoneError } from "./MySmsSettings";
import { bookingAskDeclined, inputStyle, rememberBookingAskDeclined, shouldAskAfterBooking } from "./sms";

/**
 * W3 screen 2, option B (ADR-350): right after a booking, once, «Να σου
 * στείλουμε SMS αν ακυρωθεί το μάθημα;» with the mobile. Only «Ενημερώσεις»
 * (service), never offers. Not asked where the box sends no SMS, nor to a
 * member who already answered (yes, no or STOP), nor again after «Όχι τώρα».
 */
export function AfterBookingSmsAsk({ slug, onDone }: { slug: string; onDone: () => void }) {
  const t = useTranslations("Sms");
  const locale = useLocale();
  const phoneError = usePhoneError();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const declined = bookingAskDeclined(slug, currentUser?.id);
  const mine = useQuery({ queryKey: myChannelsKey(slug), queryFn: () => fetchMyChannels(token!, slug), enabled: Boolean(token) && !declined });
  const [phone, setPhone] = useState("");
  const [current, setCurrent] = useState<string | null>(null);
  const shownPhone = current ?? mine.data?.contact?.phone ?? phone;
  const save = useMutation({
    mutationFn: () =>
      saveMyChannels(token!, slug, {
        phone: shownPhone.trim(),
        locale: smsLocale(locale),
        text_version: BOOKING_CONSENT_TEXT,
        consents: [{ channel: "sms", purpose: "service", granted: true }],
      }),
    onSuccess: (next) => {
      queryClient.setQueryData(myChannelsKey(slug), next);
      onDone();
    },
  });

  if (!token || !shouldAskAfterBooking(mine.data, declined)) return null;
  const error = save.isError ? phoneError(save.error) ?? t("errors.generic") : null;

  const notNow = () => {
    rememberBookingAskDeclined(slug, currentUser?.id);
    onDone();
  };

  return (
    <Sheet
      labelId="after-booking-sms"
      title={t("askTitle")}
      onClose={notNow}
      footer={
        <>
          <SheetButton onClick={notNow}>{t("askNo")}</SheetButton>
          <SheetButton primary disabled={save.isPending || shownPhone.trim() === ""} onClick={() => save.mutate()}>
            {t("askYes")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-2" data-testid="after-booking-sms">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("askBody")}</p>
        <label className="text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="after-booking-phone">{t("mobile")}</label>
        <input
          id="after-booking-phone"
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          value={shownPhone}
          placeholder="+30 69…"
          aria-invalid={Boolean(error)}
          aria-describedby={error ? "after-booking-phone-error" : undefined}
          onChange={(event) => {
            setCurrent(event.target.value);
            setPhone(event.target.value);
          }}
          className="rounded-xl px-3 py-2 text-sm"
          style={inputStyle(Boolean(error))}
        />
        {error ? <p id="after-booking-phone-error" className="text-xs" style={{ color: "var(--danger-strong)" }}>{error}</p> : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("askFooter")}</p>
      </div>
    </Sheet>
  );
}
