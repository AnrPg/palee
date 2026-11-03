"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useId } from "react";

import { quoteSurcharge } from "@/api/card-surcharge";
import { asksCardKind, deskCard, deskCardKinds, type DeskCardKind } from "@/components/admin/payments/card-surcharge";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import type { DeskSurcharge } from "./receive-payment";

/**
 * «Κάρτα στο POS» with a card surcharge (ADR-340; mockup W1 s3, option A).
 * Shown only when the box surcharges on its own POS: staff say what card the
 * member gave and Palee writes the amount from the box's setting. «Δεν ξέρω»
 * (the default) and cards the law protects add nothing, so a card can never
 * be surcharged unlawfully. The total to type on the POS shows large.
 */
export function DeskSurchargeQuestion({
  amountCents,
  currency,
  kind,
  onKind,
  onSurcharge,
}: {
  amountCents: number;
  currency: string;
  kind: DeskCardKind;
  onKind: (kind: DeskCardKind) => void;
  onSurcharge: (surcharge: DeskSurcharge | null) => void;
}) {
  const t = useTranslations("CardSurcharge");
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const labelId = useId();

  // Whether the question applies at all: the box's setting and its country's rule.
  const setting = useQuery({
    queryKey: ["admin", "payments", "surcharge", "desk-quote", amountCents],
    enabled: Boolean(token) && amountCents > 0,
    queryFn: () => quoteSurcharge(token, { amount_cents: amountCents, channel: "desk", card: null }),
    staleTime: 60_000,
  });
  const rule = setting.data?.rule;
  const anyCard = rule === "any" && setting.data?.applies === true;
  const asks = asksCardKind(setting.data);
  const card = anyCard ? {} : deskCard(kind);

  const quote = useQuery({
    queryKey: ["admin", "payments", "surcharge", "desk-quote", amountCents, JSON.stringify(card)],
    enabled: Boolean(token) && amountCents > 0 && (anyCard || (asks && kind !== "unknown")),
    queryFn: () => quoteSurcharge(token, { amount_cents: amountCents, channel: "desk", card }),
    staleTime: 60_000,
  });

  const applies = (anyCard || (asks && kind !== "unknown")) && quote.data?.applies === true;
  const surchargeCents = applies ? quote.data!.surcharge_cents : 0;
  const cardKey = JSON.stringify(card);

  useEffect(() => {
    onSurcharge(applies && surchargeCents > 0 ? { cents: surchargeCents, card: JSON.parse(cardKey) as Record<string, unknown> } : null);
  }, [applies, surchargeCents, cardKey, onSurcharge]);

  if (!asks && !anyCard) return null;
  const money = (cents: number) => formatMinorUnits(locale, cents, currency);

  return (
    <div className="space-y-3" data-testid="desk-surcharge">
      {asks ? (
        <div className="space-y-1.5">
          <p id={labelId} className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
            {t("deskQuestion")}
          </p>
          <div role="radiogroup" aria-labelledby={labelId} className="flex flex-wrap gap-2">
            {deskCardKinds(rule!).map((option) => {
              const on = option === kind;
              return (
                <button
                  key={option}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  data-testid={`desk-card-${option}`}
                  onClick={() => onKind(option)}
                  className="rounded-full px-3.5 py-2 text-sm font-semibold"
                  style={
                    on
                      ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                      : { background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }
                  }
                >
                  {t(`deskKind_${option}`)}
                </button>
              );
            })}
          </div>
        </div>
      ) : null}

      <div className="flex items-center justify-between gap-3 text-sm">
        <span style={{ color: "var(--text-soft)" }}>{t("deskLine")}</span>
        {applies ? (
          <span className="font-semibold tabular-nums" style={{ color: "var(--text)" }} data-testid="desk-surcharge-amount">
            {money(surchargeCents)}
          </span>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {kind === "unknown" && !anyCard ? t("deskNoneUnknown") : quote.isFetching ? "…" : t("deskNoneCard")}
          </span>
        )}
      </div>

      <div className="rounded-2xl px-4 py-3" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}>
        <p className="text-xs">{t("deskTypeOnPos")}</p>
        <p className="text-2xl font-bold tabular-nums" data-testid="desk-surcharge-total">
          {money(amountCents + surchargeCents)}
        </p>
      </div>
    </div>
  );
}
