"use client";

/**
 * ADR-770 (ANR's pick 1A): after «Αποθήκευση αλλαγών», when the package has
 * holders and a change would reach them, staff choose «Και στα ενεργά μέλη»
 * or «Μόνο στις νέες αγορές». Nothing is chosen in advance. Each change
 * says when it reaches a holder; the holders can be left out one by one.
 */
import { useState } from "react";

import type { PackageTermsPreview, TermChange, TermsChoice, TermTiming } from "@/api/finance";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { termLabel, termValue } from "@/components/finance/package-terms";
import { Dialog } from "@/components/ui/Dialog";
import type { UiTranslator } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

const TIMING_STYLE: Record<TermTiming, { background: string; color: string }> = {
  now: { background: "color-mix(in srgb, var(--success) 16%, var(--panel))", color: "var(--success)" },
  next_period: { background: "color-mix(in srgb, var(--warning) 16%, var(--panel))", color: "var(--warning)" },
  never: { background: "var(--border)", color: "var(--dim)" },
  purchase_only: { background: "var(--border)", color: "var(--dim)" },
};

export function PackageTermsApplySheet({
  preview,
  classTypeNames,
  saving,
  error,
  onCancel,
  onConfirm,
}: {
  preview: PackageTermsPreview;
  classTypeNames?: Map<string, string>;
  saving: boolean;
  error?: React.ReactNode;
  onCancel: () => void;
  onConfirm: (choice: TermsChoice) => void;
}) {
  const t = useUiTranslations() as unknown as UiTranslator;
  const locale = useUiLocale();
  const [applyTo, setApplyTo] = useState<TermsChoice["apply_to"] | null>(null);
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [showMembers, setShowMembers] = useState(false);
  const count = preview.holders_count;

  function toggle(subscriptionId: string) {
    setExcluded((previous) => {
      const next = new Set(previous);
      if (next.has(subscriptionId)) next.delete(subscriptionId);
      else next.add(subscriptionId);
      return next;
    });
  }

  function confirm() {
    if (!applyTo) return;
    onConfirm({ apply_to: applyTo, excluded_subscription_ids: applyTo === "active" ? [...excluded] : [] });
  }

  return (
    <Dialog
      onClose={onCancel}
      title={t("pkgTermsSheetTitle", { count })}
      titleId="package-terms-apply-title"
      size="lg"
      variant="sheet"
      footer={
        <div className="flex w-full flex-wrap items-center gap-3">
          <button
            type="button"
            className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-40"
            style={{ background: "var(--text)", color: "var(--bg)" }}
            disabled={!applyTo || saving}
            onClick={confirm}
            data-testid="package-terms-save"
          >
            {saving ? t("checking820d600") : t("pkgTermsSave")}
          </button>
          <button
            type="button"
            className="rounded-full px-5 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={onCancel}
          >
            {t("pkgCancel")}
          </button>
          {!applyTo ? <span className="text-xs" style={{ color: "var(--dim)" }}>{t("pkgTermsPick")}</span> : null}
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("pkgTermsSheetLead")}</p>

        <div role="radiogroup" aria-labelledby="package-terms-apply-title" className="flex flex-col gap-3">
          <Option
            checked={applyTo === "active"}
            onSelect={() => setApplyTo("active")}
            title={t("pkgTermsApplyActive")}
            hint={t("pkgTermsApplyActiveHint")}
            testId="package-terms-active"
          />
          <ul className="flex flex-col rounded-[1rem] px-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            {preview.changes.map((change) => (
              <ChangeRow key={change.key} t={t} locale={locale} change={change} names={classTypeNames} earliest={preview.earliest_next_on} />
            ))}
          </ul>
          <Option
            checked={applyTo === "new_only"}
            onSelect={() => setApplyTo("new_only")}
            title={t("pkgTermsNewOnly")}
            hint={t("pkgTermsNewOnlyHint", { count })}
            testId="package-terms-new-only"
          />
        </div>

        <button
          type="button"
          className="self-start text-sm font-semibold"
          style={{ color: "var(--primary)", minHeight: 44 }}
          aria-expanded={showMembers}
          onClick={() => setShowMembers((value) => !value)}
        >
          {t("pkgTermsMembersLink", { count })}
          {excluded.size > 0 ? ` · ${t("pkgTermsExcluded", { count: excluded.size })}` : ""}
        </button>

        {showMembers ? (
          <div className="flex flex-col gap-1" data-testid="package-terms-members">
            {applyTo === "active" ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("pkgTermsExcludeHint")}</p> : null}
            <ul className="flex flex-col">
              {preview.holders.map((holder) => (
                <li key={holder.subscription_id} className="flex items-center gap-3 py-2 text-sm" style={{ borderBottom: "1px solid var(--border)" }}>
                  {applyTo === "active" ? (
                    <input
                      type="checkbox"
                      className="h-5 w-5 shrink-0"
                      checked={!excluded.has(holder.subscription_id)}
                      onChange={() => toggle(holder.subscription_id)}
                      aria-label={holder.nickname ?? holder.user_id}
                    />
                  ) : null}
                  <span className="min-w-0 flex-1 truncate font-semibold" style={{ color: "var(--text)" }}>{holder.nickname ?? "—"}</span>
                  <span className="text-xs text-end" style={{ color: "var(--dim)" }}>
                    {[
                      holder.next_period_on ? t("pkgTermsMemberNext", { date: formatDate(locale, holder.next_period_on) }) : null,
                      ...holder.notes.map((note) => t(`pkgTermsNote_${note}`)),
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {error}
      </div>
    </Dialog>
  );
}

function Option({
  checked,
  onSelect,
  title,
  hint,
  testId,
}: {
  checked: boolean;
  onSelect: () => void;
  title: string;
  hint: string;
  testId: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={checked}
      onClick={onSelect}
      data-testid={testId}
      className="flex w-full items-center justify-between gap-3 rounded-[1rem] px-4 py-3 text-start"
      style={{
        background: "var(--panel)",
        border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`,
        boxShadow: checked ? "0 0 0 1px var(--primary)" : undefined,
        minHeight: 52,
      }}
    >
      <span className="min-w-0">
        <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</span>
        <span className="block text-xs" style={{ color: "var(--dim)" }}>{hint}</span>
      </span>
      <span aria-hidden className="text-base font-bold" style={{ color: "var(--primary)" }}>{checked ? "✓" : ""}</span>
    </button>
  );
}

function ChangeRow({
  t,
  locale,
  change,
  names,
  earliest,
}: {
  t: UiTranslator;
  locale: string;
  change: TermChange;
  names?: Map<string, string>;
  earliest: string | null;
}) {
  const style = TIMING_STYLE[change.timing];
  return (
    <li className="flex items-center gap-3 py-2" style={{ borderBottom: "1px solid var(--border)" }}>
      <span className="min-w-0 flex-1">
        <span className="block break-words text-sm font-semibold" style={{ color: "var(--text)" }}>
          {termLabel(t, change.key)}: {termValue(t, locale, change.key, change.from, names)} → {termValue(t, locale, change.key, change.to, names)}
        </span>
        {change.timing === "next_period" && earliest ? (
          <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("pkgTermsNextHint", { date: formatDate(locale, earliest) })}</span>
        ) : null}
      </span>
      <span className="shrink-0 rounded-full px-2.5 py-0.5 text-xs font-bold" style={style}>
        {t(`pkgTermsTiming_${change.timing}`)}
      </span>
    </li>
  );
}
