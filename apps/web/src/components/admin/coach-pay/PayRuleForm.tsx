"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import { ApiError } from "@/api/client";
import { archivePayRule, coachPayKeys, createPayRule, updatePayRule, type PayRule } from "@/api/coach-pay";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { useSession } from "@/components/session-provider";
import { DateInput } from "@/components/ui/DateInput";
import { DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import {
  COUNT_STATUSES,
  FREQUENCIES,
  RULE_KINDS,
  SALES_SCOPES,
  emptyRuleDraft,
  ruleBody,
  ruleDraftFrom,
  ruleErrors,
  type RuleDraft,
  type RuleField,
} from "./coach-pay";
import { Advanced, Choice, Chips, FormRow, controlClass, controlStyle, useGymToday } from "./pay-ui";

/**
 * «Νέος κανόνας · Νίκος Α.» (mockup W1 s4, option A): a side panel with the
 * ways a person is paid in plain words, the fields each one needs and the
 * dates it holds. Gross or net, class types and a note are rare, so they
 * wait under «Προχωρημένα». A rule is archived, never deleted (ADR-341).
 */
export function PayRuleForm({ userId, name, rule, onClose }: { userId: string; name: string; rule?: PayRule | null; onClose: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const today = useGymToday();
  const ids = useId();
  const [draft, setDraft] = useState<RuleDraft>(() => (rule ? ruleDraftFrom(rule) : emptyRuleDraft(today)));
  const [checked, setChecked] = useState(false);
  const [advanced, setAdvanced] = useState(Boolean(rule && (rule.amount_basis === "net" || rule.note)));

  const done = async () => {
    await queryClient.invalidateQueries({ queryKey: coachPayKeys.all });
    onClose();
  };
  const save = useMutation({
    mutationFn: () => {
      const body = ruleBody(draft, userId);
      if (!rule) return createPayRule(token, body);
      const { coach_user_id: _person, ...update } = body;
      return updatePayRule(token, rule.id, update);
    },
    onSuccess: done,
  });
  const archive = useMutation({ mutationFn: () => archivePayRule(token, rule!.id), onSuccess: done });

  const errors = checked ? ruleErrors(draft) : {};
  const serverFields = save.error instanceof ApiError ? (save.error.payload.errors ?? {}) : {};
  const serverField = (field: RuleField, key: string) => (key in serverFields ? localizeError(save.error, ui) : null);
  const message = (field: RuleField, apiKey: string) => (errors[field] ? t(errors[field]!) : serverField(field, apiKey));
  const formError = save.error && Object.keys(serverFields).length === 0 ? localizeError(save.error, ui) : archive.error ? localizeError(archive.error, ui) : null;
  const update = (patch: Partial<RuleDraft>) => setDraft({ ...draft, ...patch });

  const submit = () => {
    setChecked(true);
    if (Object.keys(ruleErrors(draft)).length > 0) return;
    save.mutate();
  };

  const amountField = (
    <FormRow label={draft.kind === "fixed" ? t("fixedAmount") : t("amount")} htmlFor={`${ids}-amount`} error={message("amount", "amount_cents")} errorId={`${ids}-amount-error`}>
      <input
        id={`${ids}-amount`}
        inputMode="decimal"
        className={controlClass + " max-w-[10rem]"}
        style={{ ...controlStyle, border: fieldBorder(message("amount", "amount_cents")) }}
        value={draft.amount}
        onChange={(event) => update({ amount: event.target.value })}
        {...invalidFieldProps(message("amount", "amount_cents"), `${ids}-amount-error`)}
      />
    </FormRow>
  );

  return (
    <SidePanel
      title={rule ? t("editRuleTitle", { name }) : t("newRuleTitle", { name })}
      subtitle={t("rulesEyebrow")}
      onClose={onClose}
      footer={
        <div className="flex flex-wrap items-center justify-between gap-2">
          {rule ? (
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--danger)" }} disabled={archive.isPending} onClick={() => archive.mutate()} data-testid="pay-rule-archive">
              {t("archiveRule")}
            </button>
          ) : (
            <span />
          )}
          <div className="flex items-center gap-2">
            <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
            <DialogButton tone="primary" disabled={save.isPending} onClick={submit} testId="pay-rule-save">
              {t("saveRule")}
            </DialogButton>
          </div>
        </div>
      }
    >
      <div className="space-y-5" data-testid="pay-rule-form">
        <FormRow label={t("howPaid")}>
          <div role="radiogroup" aria-label={t("howPaid")} className="space-y-2">
            {RULE_KINDS.map((kind) => {
              const on = draft.kind === kind;
              return (
                <button
                  key={kind}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  data-testid={`pay-rule-kind-${kind}`}
                  onClick={() => update({ kind })}
                  className="flex w-full items-start gap-3 rounded-2xl p-3 text-start"
                  style={{ background: on ? "color-mix(in srgb, var(--primary) 8%, var(--panel))" : "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}` }}
                >
                  <span aria-hidden="true" className="mt-1 inline-block h-4 w-4 shrink-0 rounded-full" style={{ border: `5px solid ${on ? "var(--primary)" : "var(--border)"}` }} />
                  <span>
                    <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`kind_${kind}`)}</span>
                    <span className="block text-xs" style={{ color: "var(--dim)" }}>{t(`kindHint_${kind}`)}</span>
                  </span>
                </button>
              );
            })}
          </div>
        </FormRow>

        {draft.kind === "percent_of_sales" ? (
          <>
            <FormRow label={t("percent")} htmlFor={`${ids}-percent`} error={message("percent", "percent_bps")} errorId={`${ids}-percent-error`}>
              <div className="flex items-center gap-2">
                <input
                  id={`${ids}-percent`}
                  inputMode="decimal"
                  className={controlClass + " max-w-[8rem]"}
                  style={{ ...controlStyle, border: fieldBorder(message("percent", "percent_bps")) }}
                  value={draft.percent}
                  onChange={(event) => update({ percent: event.target.value })}
                  {...invalidFieldProps(message("percent", "percent_bps"), `${ids}-percent-error`)}
                />
                <span className="text-sm" style={{ color: "var(--dim)" }}>%</span>
              </div>
            </FormRow>
            <FormRow label={t("salesFrom")}>
              <Choice label={t("salesFrom")} value={draft.salesScope} onChange={(salesScope) => update({ salesScope })} options={SALES_SCOPES.map((scope) => ({ value: scope, label: t(`scope_${scope}`) }))} />
            </FormRow>
          </>
        ) : (
          amountField
        )}

        {draft.kind === "per_class" ? (
          <FormRow label={t("minAttendees")} htmlFor={`${ids}-min`} hint={t("minAttendeesHint")} error={message("minAttendees", "min_attendees")} errorId={`${ids}-min-error`}>
            <input
              id={`${ids}-min`}
              inputMode="numeric"
              className={controlClass + " max-w-[8rem]"}
              style={{ ...controlStyle, border: fieldBorder(message("minAttendees", "min_attendees")) }}
              value={draft.minAttendees}
              onChange={(event) => update({ minAttendees: event.target.value })}
              {...invalidFieldProps(message("minAttendees", "min_attendees"), `${ids}-min-error`)}
            />
          </FormRow>
        ) : null}

        {draft.kind === "per_attendee" ? (
          <FormRow label={t("counted")} error={message("countStatuses", "count_statuses")} errorId={`${ids}-counted-error`}>
            <Chips
              label={t("counted")}
              invalid={Boolean(message("countStatuses", "count_statuses"))}
              value={draft.countStatuses}
              onChange={(countStatuses) => update({ countStatuses })}
              options={COUNT_STATUSES.map((status) => ({ value: status, label: t(`count_${status}`) }))}
            />
          </FormRow>
        ) : null}

        {draft.kind === "fixed" ? (
          <FormRow label={t("frequency")}>
            <Choice label={t("frequency")} value={draft.frequency} onChange={(frequency) => update({ frequency })} options={FREQUENCIES.map((frequency) => ({ value: frequency, label: t(`frequency_${frequency}`) }))} />
          </FormRow>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <FormRow label={t("from")} error={message("startsOn", "starts_on")} errorId={`${ids}-from-error`}>
            <DateInput
              aria-label={t("from")}
              className={controlClass}
              style={{ ...controlStyle, border: fieldBorder(message("startsOn", "starts_on")) }}
              value={draft.startsOn}
              onValueChange={(startsOn) => update({ startsOn })}
            />
          </FormRow>
          <FormRow label={t("until")} hint={t("untilHint")} error={message("endsOn", "ends_on")} errorId={`${ids}-until-error`}>
            <DateInput
              aria-label={t("until")}
              className={controlClass}
              style={{ ...controlStyle, border: fieldBorder(message("endsOn", "ends_on")) }}
              value={draft.endsOn}
              onValueChange={(endsOn) => update({ endsOn })}
            />
          </FormRow>
        </div>

        <Advanced open={advanced} onToggle={() => setAdvanced((value) => !value)}>
          <FormRow label={t("basis")} hint={t("basisHint")}>
            <Choice label={t("basis")} value={draft.basis} onChange={(basis) => update({ basis })} options={[{ value: "gross", label: t("gross") }, { value: "net", label: t("net") }]} testId="pay-rule-basis" />
          </FormRow>
          <FormRow label={t("note")} htmlFor={`${ids}-note`}>
            <input id={`${ids}-note`} className={controlClass} style={{ ...controlStyle, border: "1px solid var(--border)" }} maxLength={500} value={draft.note} onChange={(event) => update({ note: event.target.value })} />
          </FormRow>
        </Advanced>

        {formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
      </div>
    </SidePanel>
  );
}
