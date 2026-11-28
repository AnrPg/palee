"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";

import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

/**
 * ADR-795 (2A): giving a package says what happened with its money, so a
 * package never needs a payment that did not happen. «Θα πληρώσει
 * αργότερα» leaves it owed; «Τα πήρα τώρα» goes on to «Καταγραφή πληρωμής»;
 * «Χωρίς χρέωση» gives it free (ADR-612), with an optional reason, after one
 * more look (it is always asked).
 */
export function PackageActivationChoice({
  packageName,
  priceCents,
  pending,
  onLater,
  onPaidNow,
  onFree,
  onBack,
}: {
  packageName: string;
  priceCents: number;
  pending: boolean;
  onLater: () => void | Promise<void>;
  onPaidNow?: () => void | Promise<void>;
  onFree?: (reason: string | null) => void | Promise<void>;
  onBack: () => void;
}) {
  const t = useTranslations("PackageActivation");
  const locale = useUiLocale();
  const [free, setFree] = useState(false);
  const [reason, setReason] = useState("");
  const amount = formatMinorUnits(locale, priceCents);

  if (free && onFree) {
    return (
      <div className="flex flex-col gap-2" data-testid="package-activate-free-confirm">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("freeConfirm", { package: packageName, amount })}
        </p>
        <label className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("freeReason")}
          <textarea
            value={reason}
            maxLength={500}
            rows={2}
            onChange={(event) => setReason(event.target.value)}
            className="mt-1 w-full rounded-lg px-3 py-2 text-sm"
            style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
            data-testid="package-activate-free-reason"
          />
        </label>
        <button
          type="button"
          disabled={pending}
          onClick={() => void onFree(reason.trim() || null)}
          className="w-full rounded-lg px-3 py-2.5 text-sm font-semibold disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="package-activate-free-submit"
        >
          {t("freeSubmit")}
        </button>
        <button type="button" onClick={() => setFree(false)} className="text-start text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("back")}
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2" data-testid="package-activate-money">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("moneyQuestion", { amount })}</p>
      <Choice testId="package-activate-later" title={t("later")} hint={t("laterHint")} disabled={pending} onClick={() => void onLater()} />
      {onPaidNow ? (
        <Choice testId="package-activate-paid-now" title={t("paidNow")} hint={t("paidNowHint")} disabled={pending} onClick={() => void onPaidNow()} />
      ) : null}
      {onFree ? (
        <Choice testId="package-activate-free" title={t("free")} hint={t("freeHint")} disabled={pending} onClick={() => setFree(true)} />
      ) : null}
      <button type="button" onClick={onBack} className="text-start text-xs font-semibold" style={{ color: "var(--dim)" }}>
        {t("back")}
      </button>
    </div>
  );
}

function Choice({ title, hint, onClick, disabled, testId }: { title: string; hint: string; onClick: () => void; disabled: boolean; testId: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="w-full rounded-lg px-3 py-2 text-start disabled:opacity-40"
      style={{ background: "var(--panel)", border: "1px solid var(--border-strong)" }}
      data-testid={testId}
    >
      <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</span>
      <span className="block text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</span>
    </button>
  );
}
