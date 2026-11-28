"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type CSSProperties, type ReactNode } from "react";

import { createFinanceInvoice, type FinanceRecord } from "@/api/finance";
import { parseAmountCents } from "@/components/admin/finance/payments/receive-payment";
import { ChargeCategorySelect } from "@/components/admin/finance/shared/ChargeCategorySelect";
import { CHARGE_CATEGORY_LABEL_KEYS, isChargeCategory, manualInvoiceBody } from "@/components/admin/finance/shared/charge-category";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

const CONTROL: CSSProperties = { background: "var(--panel)", color: "var(--text)" };

/**
 * ADR-784 (ANR pick 6): «+ Χρέωση για κάτι νέο». Staff who manage billing
 * charge a person for something beyond their package (a product, a personal
 * training, an event, anything else). It goes into what they owe and shows in
 * their movements. «Χρέωση και πληρωμή τώρα» charges it and opens the payment
 * on that same charge, for a sale paid on the spot.
 */
export function NewChargeDialog({
  token,
  userId,
  nickname,
  canTakePayment,
  onClose,
  onCharged,
}: {
  token: string;
  userId: string;
  nickname: string;
  /** Shows «Χρέωση και πληρωμή τώρα» (take_payments). */
  canTakePayment: boolean;
  onClose: () => void;
  /** The new charge; `payNow` when staff asked to take the money at once. */
  onCharged: (invoice: FinanceRecord, payNow: boolean) => void;
}) {
  const t = useTranslations("MemberFinance");
  const i18n = useUiTranslations();
  const ids = useId();
  const [category, setCategory] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [checked, setChecked] = useState(false);
  const [payNow, setPayNow] = useState(false);

  const amountCents = parseAmountCents(amount);
  const missing = {
    category: checked && !isChargeCategory(category) ? t("chargeCategoryMissing") : null,
    amount: checked && amountCents === null ? t("chargeAmountInvalid") : null,
  };

  const mutation = useMutation({
    mutationFn: () =>
      createFinanceInvoice(
        token,
        userId,
        manualInvoiceBody({
          amountCents: amountCents ?? 0,
          description,
          dueDate,
          subscriptionId: "",
          chargeCategory: category,
          fallbackDescription: isChargeCategory(category) ? i18n(CHARGE_CATEGORY_LABEL_KEYS[category]) : "",
        }),
      ),
    onSuccess: ({ invoice }) => onCharged(invoice, payNow),
  });

  function submit(now: boolean) {
    setChecked(true);
    if (!isChargeCategory(category) || amountCents === null) return;
    setPayNow(now);
    mutation.mutate();
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("newChargeTitle")}
      description={t("newChargeHint", { name: nickname })}
      size="md"
      variant="center"
      dismissible={!mutation.isPending}
      testId="new-charge"
      onSubmit={(event) => {
        event.preventDefault();
        submit(false);
      }}
      error={mutation.error ? <ErrorNotice variant="field">{localizeError(mutation.error, i18n)}</ErrorNotice> : null}
      footer={
        <>
          {canTakePayment ? (
            <DialogButton type="button" tone="secondary" disabled={mutation.isPending} onClick={() => submit(true)} testId="new-charge-pay-now">
              {t("chargeAndPay")}
            </DialogButton>
          ) : null}
          <DialogButton type="submit" tone="primary" disabled={mutation.isPending} testId="new-charge-save">
            {mutation.isPending ? t("charging") : t("charge")}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <Row label={i18n("admChargeCategory")} errorId={`${ids}-category`} error={missing.category}>
          <ChargeCategorySelect
            className="w-full rounded-xl px-3 py-2.5 text-sm"
            style={{ ...CONTROL, border: fieldBorder(missing.category) }}
            value={category}
            onChange={setCategory}
          />
        </Row>
        <Row label={t("chargeDescription")}>
          <input
            aria-label={t("chargeDescription")}
            className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
            style={{ ...CONTROL, border: "1px solid var(--border)" }}
            value={description}
            maxLength={500}
            placeholder={t("chargeDescriptionHint")}
            onChange={(event) => setDescription(event.target.value)}
          />
        </Row>
        <Row label={t("chargeAmount")} errorId={`${ids}-amount`} error={missing.amount}>
          <input
            aria-label={t("chargeAmount")}
            className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
            style={{ ...CONTROL, border: fieldBorder(missing.amount) }}
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            {...invalidFieldProps(missing.amount, `${ids}-amount`)}
          />
        </Row>
        <Row label={t("chargeDue")} hint={t("chargeDueHint")}>
          <DateInput
            aria-label={t("chargeDue")}
            className="w-full rounded-xl px-3 py-2.5 text-sm"
            style={{ ...CONTROL, border: "1px solid var(--border)" }}
            value={dueDate}
            onValueChange={setDueDate}
          />
        </Row>
      </div>
    </Dialog>
  );
}

function Row({ label, hint, error, errorId, children }: { label: string; hint?: string; error?: string | null; errorId?: string; children: ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{label}</p>
      {children}
      {hint && !error ? <p className="text-xs" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      {errorId ? <FieldError id={errorId}>{error}</FieldError> : null}
    </div>
  );
}
