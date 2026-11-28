"use client";

/**
 * ADR-795: a package that waits for the member's first completed class or
 * WOD («Ξεκινά με την πρώτη σου προπόνηση»), or that changed while it waited
 * and starts only after the member's «Το κατάλαβα». The member sees the
 * button; staff (the member's profile) see the same state, read only.
 */
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError, type UiTranslator } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { PRICE_KEY, termLabel, termValue } from "./package-terms";

/** The shape both the member's billing and the staff profile return. */
export type PackageStartView = {
  id: string;
  status: "waiting" | "review" | string;
  package_name: string;
  waiting_since: string;
  severity?: "important" | "serious" | "warning" | string | null;
  changes: Array<{ key: string; from?: unknown; to?: unknown; severity: string }>;
};

const TONE: Record<string, string> = {
  important: "var(--danger)",
  serious: "var(--warning)",
  warning: "var(--primary)",
};

export function PackageStartNotice({
  start,
  audience,
  onAcknowledge,
  pending = false,
  error = null,
}: {
  start: PackageStartView | null | undefined;
  audience: "member" | "staff";
  onAcknowledge?: () => void;
  pending?: boolean;
  error?: unknown;
}) {
  const t = useUiTranslations() as unknown as UiTranslator;
  const locale = useUiLocale();
  if (!start) return null;

  if (start.status === "waiting") {
    return (
      <div
        className="rounded-[1rem] px-3 py-2"
        style={{ background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid var(--border)" }}
        data-testid="package-start-waiting"
      >
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {audience === "member" ? t("pkgStartWaitingMember") : t("pkgStartWaitingStaff")}
        </p>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
          {t("pkgStartWaitingHint", { date: formatDate(locale, start.waiting_since) })}
        </p>
      </div>
    );
  }

  const severity = start.severity ?? "warning";
  const tone = TONE[severity] ?? TONE.warning;
  const priceUp = start.changes.some((change) => change.key === PRICE_KEY && change.severity === "important");

  return (
    <div
      className="rounded-[1rem] px-3 py-3"
      style={{ background: `color-mix(in srgb, ${tone} 10%, var(--panel))`, border: `1px solid ${tone}` }}
      role={audience === "member" ? "alert" : undefined}
      data-testid="package-start-review"
      data-severity={severity}
    >
      <p className="text-sm font-bold" style={{ color: "var(--text)" }}>
        {t(`pkgStartReview_${severity}`, { package: start.package_name })}
      </p>
      <p className="mt-0.5 text-xs leading-5" style={{ color: "var(--text-soft)" }}>
        {audience === "member" ? t("pkgStartReviewHintMember") : t("pkgStartReviewHintStaff")}
      </p>
      <ul className="mt-2 flex flex-col gap-0.5 text-sm" style={{ color: "var(--text-soft)" }}>
        {start.changes.map((change) => (
          <li key={change.key} className="break-words" data-severity={change.severity}>
            {change.key === "name" ? t("pkgStartName") : termLabel(t, change.key)}:{" "}
            {change.key === "name" ? String(change.from ?? "") : termValue(t, locale, change.key, change.from)} →{" "}
            <b style={{ color: "var(--text)" }}>
              {change.key === "name" ? String(change.to ?? "") : termValue(t, locale, change.key, change.to)}
            </b>
          </li>
        ))}
      </ul>
      {priceUp ? (
        <p className="mt-2 text-xs leading-5" style={{ color: "var(--text-soft)" }}>{t("pkgStartFirstPeriodPrice")}</p>
      ) : null}
      {audience === "member" && onAcknowledge ? (
        <button
          type="button"
          onClick={onAcknowledge}
          disabled={pending}
          className="mt-3 min-h-11 w-full rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="package-start-acknowledge"
        >
          {t("pkgStartAcknowledge")}
        </button>
      ) : null}
      {error ? <ErrorNotice variant="field">{localizeError(error, t)}</ErrorNotice> : null}
    </div>
  );
}
