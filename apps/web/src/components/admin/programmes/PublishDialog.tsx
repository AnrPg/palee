"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useId, useState } from "react";

import {
  PROGRAMME_REFUND_POLICIES,
  publishProgramme,
  STAFF_PROGRAMMES_KEY,
  staffProgrammeKey,
  updateProgramme,
  type ProgrammeListing,
  type ProgrammeRefundPolicy,
  type StaffProgramme,
} from "@/api/programmes";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";

import { emptyWeeks } from "@/components/programmes/programme-grid";
import { programmeMoney, useProgrammeError } from "@/components/programmes/programme-ui";

/**
 * «Δημοσίευση…» (mockup W8 s2 A): the price and where the programme shows,
 * with the refund rule and preview days under «Προχωρημένα».
 */
export function PublishDialog({
  programme,
  token,
  onClose,
  beforePublish,
}: {
  programme: StaffProgramme;
  token: string;
  onClose: () => void;
  /** Saves the editor's unsaved changes first, so the version holds what the coach sees. */
  beforePublish?: () => Promise<void>;
}) {
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
      await beforePublish?.();
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
