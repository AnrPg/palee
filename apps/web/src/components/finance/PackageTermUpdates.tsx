"use client";

/**
 * ADR-770: the package changes that reached a subscription, read the same
 * by the member (Εγώ › Πληρωμές) and by staff (the member's profile):
 * «Νέοι όροι από …» while one waits for the next period, then
 * «Όροι ενημερώθηκαν στις …» for the ones already in force.
 */
import { formatDate } from "@/components/finance/MembershipEntitlement";
import type { UiTranslator } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { termLabel, termValue } from "./package-terms";

/** The shape both the member's billing and the staff profile return. */
type TermUpdate = {
  id: string;
  status: string;
  effective_on: string;
  applied_at?: string | null;
  changes: Array<{ key: string; from?: unknown; to?: unknown }>;
};

export function PackageTermUpdates({ updates }: { updates: TermUpdate[] | null | undefined }) {
  const t = useUiTranslations() as unknown as UiTranslator;
  const locale = useUiLocale();
  const list = (updates ?? []).filter((update) => update.changes.length > 0);
  if (list.length === 0) return null;

  const pending = list.filter((update) => update.status === "pending");
  const applied = list.filter((update) => update.status === "applied").slice(0, 3);

  return (
    <div className="flex flex-col gap-2" data-testid="package-term-updates">
      {pending.map((update) => (
        <div
          key={update.id}
          className="rounded-[1rem] px-3 py-2"
          style={{ background: "color-mix(in srgb, var(--warning) 10%, var(--panel))", border: "1px solid var(--border)" }}
        >
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("pkgTermsNewTermsFrom", { date: formatDate(locale, update.effective_on) })}
          </p>
          <ChangeList t={t} locale={locale} update={update} />
        </div>
      ))}
      {applied.length > 0 ? (
        <details className="text-sm" style={{ color: "var(--text-soft)" }}>
          <summary className="cursor-pointer font-semibold">{t("pkgTermsHistory")}</summary>
          <div className="mt-2 flex flex-col gap-2">
            {applied.map((update) => (
              <div key={update.id}>
                <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
                  {t("pkgTermsUpdatedOn", { date: formatDate(locale, update.applied_at ?? update.effective_on) })}
                </p>
                <ChangeList t={t} locale={locale} update={update} />
              </div>
            ))}
          </div>
        </details>
      ) : null}
    </div>
  );
}

function ChangeList({ t, locale, update }: { t: UiTranslator; locale: string; update: TermUpdate }) {
  return (
    <ul className="mt-1 flex flex-col gap-0.5 text-sm" style={{ color: "var(--text-soft)" }}>
      {update.changes.map((change) => (
        <li key={change.key} className="break-words">
          {termLabel(t, change.key)}: {termValue(t, locale, change.key, change.from)} → <b style={{ color: "var(--text)" }}>{termValue(t, locale, change.key, change.to)}</b>
        </li>
      ))}
    </ul>
  );
}
