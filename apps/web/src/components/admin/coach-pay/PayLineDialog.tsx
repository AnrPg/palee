"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import { ApiError } from "@/api/client";
import { addPayAdjustment, addPayItemLine, coachPayKeys, fetchPayItems, reopenPayPeriod, type PayPeriod } from "@/api/coach-pay";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import {
  ADJUSTMENT_KINDS,
  addableItems,
  adjustmentBody,
  defaultBasis,
  emptyLineDraft,
  lineErrors,
  type LineDraft,
  type LineField,
} from "./coach-pay";
import { Advanced, Choice, FormRow, controlClass, controlStyle, useMoney } from "./pay-ui";

/**
 * «Προσθήκη γραμμής · Νίκος Α.» in a draft period (ADR-341/382; mockup W1 s5
 * «+ Διόρθωση»): a correction (may be negative), an ad hoc payment, «Μη
 * φορολογητέο» or an allowance from the box's catalogue. Every line by hand
 * needs its reason; «Μη φορολογητέο» starts as net, the rest as gross, and
 * the basis can change under «Προχωρημένα».
 */
export function PayLineDialog({ period, userId, name, onClose }: { period: PayPeriod; userId: string; name: string; onClose: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const money = useMoney(period.currency);
  const [draft, setDraft] = useState<LineDraft>(emptyLineDraft);
  const [checked, setChecked] = useState(false);
  const [advanced, setAdvanced] = useState(false);

  const itemsQuery = useQuery({ queryKey: coachPayKeys.items, enabled: Boolean(token), queryFn: () => fetchPayItems(token) });
  const allowances = addableItems(itemsQuery.data?.items ?? []);
  const item = allowances.find((candidate) => candidate.id === draft.itemId) ?? null;

  const save = useMutation({
    mutationFn: () =>
      draft.kind === "allowance"
        ? addPayItemLine(token, period.id, {
            user_id: userId,
            pay_item_id: draft.itemId,
            ...(item?.unit === "per_occurrence" ? { quantity: Number(draft.quantity) } : {}),
            note: draft.note.trim() || null,
            amount_basis: draft.basis,
          })
        : addPayAdjustment(token, period.id, adjustmentBody(draft, userId)),
    onSuccess: ({ period: next }) => {
      queryClient.setQueryData(coachPayKeys.period(period.id), { period: next });
      void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
      onClose();
    },
  });

  const errors = checked ? lineErrors(draft, item) : {};
  const serverFields = save.error instanceof ApiError ? (save.error.payload.errors ?? {}) : {};
  const apiKey: Record<LineField, string> = { amount: "amount_cents", note: "note", itemId: "pay_item_id", quantity: "quantity" };
  const message = (field: LineField) => (errors[field] ? t(errors[field]!) : apiKey[field] in serverFields ? localizeError(save.error, ui) : null);
  const formError = save.error && Object.keys(serverFields).length === 0 ? localizeError(save.error, ui) : null;

  const kinds = [...ADJUSTMENT_KINDS, ...(allowances.length > 0 ? (["allowance"] as const) : [])];
  const setKind = (kind: LineDraft["kind"]) =>
    setDraft({ ...draft, kind, basis: kind === "allowance" ? (allowances.find((entry) => entry.id === draft.itemId)?.amount_basis ?? "gross") : defaultBasis(kind) });

  return (
    <Dialog
      onClose={onClose}
      title={t("addLineTitle", { name })}
      size="md"
      variant="center"
      dismissible={!save.isPending}
      testId="pay-line-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (Object.keys(lineErrors(draft, item)).length > 0) return;
        save.mutate();
      }}
      error={formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" disabled={save.isPending} testId="pay-line-save">
            {t("addLine")}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <FormRow label={t("lineKind")}>
          <Choice label={t("lineKind")} value={draft.kind} onChange={setKind} options={kinds.map((kind) => ({ value: kind, label: t(`kind_${kind}`) }))} testId="pay-line-kind" />
        </FormRow>

        {draft.kind === "allowance" ? (
          <>
            <FormRow label={t("allowance")} error={message("itemId")} errorId={`${ids}-item-error`}>
              <Select
                aria-label={t("allowance")}
                className={controlClass}
                style={{ ...controlStyle, border: fieldBorder(message("itemId")) }}
                value={draft.itemId}
                onValueChange={(itemId) => setDraft({ ...draft, itemId, basis: allowances.find((entry) => entry.id === itemId)?.amount_basis ?? draft.basis })}
                {...invalidFieldProps(message("itemId"), `${ids}-item-error`)}
              >
                <option value="">{t("pickAllowance")}</option>
                {allowances.map((entry) => (
                  <option key={entry.id} value={entry.id}>
                    {`${entry.name} · ${money(entry.amount_cents)}`}
                  </option>
                ))}
              </Select>
            </FormRow>
            {item?.unit === "per_occurrence" ? (
              <FormRow label={t("times")} htmlFor={`${ids}-qty`} error={message("quantity")} errorId={`${ids}-qty-error`}>
                <input
                  id={`${ids}-qty`}
                  inputMode="numeric"
                  className={controlClass + " max-w-[8rem]"}
                  style={{ ...controlStyle, border: fieldBorder(message("quantity")) }}
                  value={draft.quantity}
                  onChange={(event) => setDraft({ ...draft, quantity: event.target.value })}
                  {...invalidFieldProps(message("quantity"), `${ids}-qty-error`)}
                />
              </FormRow>
            ) : null}
          </>
        ) : (
          <FormRow
            label={t("amount")}
            htmlFor={`${ids}-amount`}
            hint={draft.kind === "adjustment" ? t("adjustmentHint") : undefined}
            error={message("amount")}
            errorId={`${ids}-amount-error`}
          >
            <input
              id={`${ids}-amount`}
              inputMode="decimal"
              className={controlClass + " max-w-[10rem]"}
              style={{ ...controlStyle, border: fieldBorder(message("amount")) }}
              value={draft.amount}
              onChange={(event) => setDraft({ ...draft, amount: event.target.value })}
              {...invalidFieldProps(message("amount"), `${ids}-amount-error`)}
            />
          </FormRow>
        )}

        <FormRow label={draft.kind === "allowance" ? t("noteOptional") : t("noteRequired")} htmlFor={`${ids}-note`} error={message("note")} errorId={`${ids}-note-error`}>
          <input
            id={`${ids}-note`}
            className={controlClass}
            style={{ ...controlStyle, border: fieldBorder(message("note")) }}
            maxLength={500}
            placeholder={t("notePlaceholder")}
            value={draft.note}
            onChange={(event) => setDraft({ ...draft, note: event.target.value })}
            {...invalidFieldProps(message("note"), `${ids}-note-error`)}
          />
        </FormRow>

        <Advanced open={advanced} onToggle={() => setAdvanced((value) => !value)}>
          <FormRow label={t("basis")} hint={t("basisHint")}>
            <Choice label={t("basis")} value={draft.basis} onChange={(basis) => setDraft({ ...draft, basis })} options={[{ value: "gross", label: t("gross") }, { value: "net", label: t("net") }]} testId="pay-line-basis" />
          </FormRow>
        </Advanced>
      </div>
    </Dialog>
  );
}

/** «Άνοιγμα ξανά»: an approved period opens again only with a reason (ADR-341). */
export function ReopenDialog({ period, onClose }: { period: PayPeriod; onClose: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const [reason, setReason] = useState("");
  const [checked, setChecked] = useState(false);
  const reopen = useMutation({
    mutationFn: () => reopenPayPeriod(token, period.id, reason.trim()),
    onSuccess: ({ period: next }) => {
      queryClient.setQueryData(coachPayKeys.period(period.id), { period: next });
      void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
      onClose();
    },
  });
  const error = checked && reason.trim() === "" ? t("errorReasonRequired") : null;
  return (
    <Dialog
      onClose={onClose}
      title={t("reopenTitle")}
      size="sm"
      variant="center"
      testId="pay-reopen-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (reason.trim() === "") return;
        reopen.mutate();
      }}
      error={reopen.isError ? <ErrorNotice variant="field">{localizeError(reopen.error, ui)}</ErrorNotice> : null}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" disabled={reopen.isPending} testId="pay-reopen-confirm">
            {t("reopen")}
          </DialogButton>
        </>
      }
    >
      <FormRow label={t("reopenWhy")} htmlFor={`${ids}-reason`} error={error} errorId={`${ids}-reason-error`}>
        <input
          id={`${ids}-reason`}
          className={controlClass}
          style={{ ...controlStyle, border: fieldBorder(error) }}
          maxLength={500}
          placeholder={t("reopenPlaceholder")}
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          {...invalidFieldProps(error, `${ids}-reason-error`)}
        />
      </FormRow>
    </Dialog>
  );
}
