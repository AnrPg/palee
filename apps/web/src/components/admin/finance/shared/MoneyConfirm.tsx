"use client";

/**
 * ADR-795: «Έλαβες πραγματικά τα χρήματα;» before money is written down
 * (a payment, «Εισπράχθηκαν» / «Είσπραξη» at the desk, an e-shop pickup paid
 * at the desk) or given back in cash. «Να μην εμφανιστεί ξανά σήμερα» holds
 * for this staff member on every device of the account until the box's
 * midnight. The way out says how to start a package without inventing a
 * payment.
 */
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import {
  CONFIRMATION_SKIPS_KEY,
  fetchConfirmationSkips,
  skipConfirmationToday,
  type MoneyConfirmationKind,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";

/** Whether the question is to be asked now (false while the skips load: asking is the safe side). */
export function useMoneyConfirmation(kind: MoneyConfirmationKind) {
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const skips = useQuery({
    queryKey: CONFIRMATION_SKIPS_KEY,
    queryFn: () => fetchConfirmationSkips(token!),
    enabled: Boolean(token),
    staleTime: 60_000,
  });
  const skip = useMutation({
    mutationFn: () => skipConfirmationToday(token!, kind),
    onSuccess: (data) => queryClient.setQueryData(CONFIRMATION_SKIPS_KEY, data),
  });
  const skipped = skips.data?.skipped.includes(kind) ?? false;
  return { ask: !skipped, skipToday: () => skip.mutateAsync() };
}

export function MoneyConfirmDialog({
  kind,
  amount,
  detail,
  wayOut,
  onConfirm,
  onBack,
  pending = false,
}: {
  kind: MoneyConfirmationKind;
  /** The amount as the box writes it, e.g. «45,00 €». */
  amount: string;
  /** One more line: who, with what method, for what. */
  detail?: ReactNode;
  /** The way out (3A): what to do instead when no money changed hands. */
  wayOut?: { text: string; action: string; onChoose: () => void };
  onConfirm: () => void;
  onBack: () => void;
  pending?: boolean;
}) {
  const t = useTranslations("MoneyConfirm");
  const { skipToday } = useMoneyConfirmation(kind);
  const [notToday, setNotToday] = useState(false);
  const [saving, setSaving] = useState(false);

  async function confirm() {
    if (notToday) {
      setSaving(true);
      try {
        await skipToday();
      } catch {
        // The question simply comes again next time; the money is what matters now.
      } finally {
        setSaving(false);
      }
    }
    onConfirm();
  }

  return (
    <Dialog
      onClose={onBack}
      title={t(`title_${kind}`, { amount })}
      size="sm"
      variant="center"
      dismissible={!pending && !saving}
      testId="money-confirm"
      footer={
        <>
          <DialogButton onClick={onBack} disabled={pending || saving} testId="money-confirm-back">
            {t("back")}
          </DialogButton>
          <DialogButton tone="primary" onClick={() => void confirm()} disabled={pending || saving} testId="money-confirm-yes">
            {t(`yes_${kind}`)}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-3">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t(`body_${kind}`)}</p>
        {detail ? <div className="text-sm" style={{ color: "var(--text)" }}>{detail}</div> : null}
        {wayOut ? (
          <div className="rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{wayOut.text}</p>
            <button
              type="button"
              onClick={wayOut.onChoose}
              disabled={pending || saving}
              className="mt-2 text-sm font-semibold"
              style={{ color: "var(--primary)" }}
              data-testid="money-confirm-way-out"
            >
              {wayOut.action}
            </button>
          </div>
        ) : null}
        <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
          <input
            type="checkbox"
            checked={notToday}
            onChange={(event) => setNotToday(event.target.checked)}
            data-testid="money-confirm-not-today"
          />
          {t("notToday")}
        </label>
      </div>
    </Dialog>
  );
}
