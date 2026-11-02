"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import { ApiError } from "@/api/client";
import { archivePayItem, coachPayKeys, createPayItem, fetchPayItems, updatePayItem, type PayItem } from "@/api/coach-pay";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import { PAY_ROLES, emptyItemDraft, itemBody, itemDraftFrom, itemErrors, type ItemDraft, type ItemField } from "./coach-pay";
import { Advanced, Chips, Choice, FormRow, NetMark, controlClass, controlStyle, useMoney } from "./pay-ui";

/**
 * «Υπερωρίες και επιδόματα» (ADR-382; product owner W1 s4): the box's
 * catalogue of overtime rates and allowances, with the roles each applies to.
 * The same list lives in Settings and in Οικονομικά › Αμοιβές coaches.
 * Overtime is calculated from the hours above the weekly threshold; an
 * allowance is added to a statement by hand. Items are archived, never deleted.
 */
export function PayItemsCatalog({ canEdit }: { canEdit: boolean }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const [editing, setEditing] = useState<{ item: PayItem | null; kind: PayItem["kind"] } | null>(null);
  const query = useQuery({ queryKey: coachPayKeys.items, enabled: Boolean(token), queryFn: () => fetchPayItems(token) });

  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;
  const items = (query.data?.items ?? []).filter((item) => !item.archived_at);

  return (
    <section className="space-y-4" data-testid="pay-items">
      {(["overtime", "allowance"] as const).map((kind) => {
        const list = items.filter((item) => item.kind === kind);
        return (
          <div key={kind} className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
              <h4 className="flex-1 font-semibold" style={{ color: "var(--text)" }}>{t(`items_${kind}`)}</h4>
              {canEdit ? (
                <button
                  type="button"
                  className="rounded-full px-3 py-1.5 text-sm font-semibold"
                  style={{ color: "var(--primary)", border: "1px solid var(--border)" }}
                  onClick={() => setEditing({ item: null, kind })}
                  data-testid={`pay-add-item-${kind}`}
                >
                  {t(`addItem_${kind}`)}
                </button>
              ) : null}
            </div>
            {list.length === 0 ? <p className="px-4 py-3 text-sm" style={{ color: "var(--dim)" }}>{t(`noItems_${kind}`)}</p> : null}
            <ul>
              {list.map((item) => (
                <li key={item.id} className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }} data-testid="pay-item">
                  <ItemRow item={item} onOpen={canEdit ? () => setEditing({ item, kind }) : undefined} />
                </li>
              ))}
            </ul>
          </div>
        );
      })}
      {editing ? <PayItemDialog item={editing.item} kind={editing.kind} onClose={() => setEditing(null)} /> : null}
    </section>
  );
}

function ItemRow({ item, onOpen }: { item: PayItem; onOpen?: () => void }) {
  const t = useTranslations("CoachPay");
  const money = useMoney(item.currency);
  const roles = item.roles.map((role) => t(`role_${role}`)).join(", ");
  const content = (
    <span className="flex w-full flex-wrap items-center gap-2 px-4 py-3 text-start">
      <span className="min-w-0 flex-1">
        <span className="block font-semibold" style={{ color: "var(--text)" }}>{item.name}</span>
        <span className="block text-xs" style={{ color: "var(--dim)" }}>
          {item.kind === "overtime" ? t("overtimeAbove", { hours: item.weekly_threshold ?? 0 }) : t(`unit_${item.unit}`)}
          {" · "}
          {roles}
        </span>
      </span>
      {item.amount_basis === "net" ? <NetMark /> : null}
      <span className="text-sm font-semibold tabular-nums" style={{ color: "var(--text)" }}>
        {item.kind === "overtime" ? t("perHourAmount", { amount: money(item.amount_cents) }) : money(item.amount_cents)}
      </span>
    </span>
  );
  if (!onOpen) return content;
  return (
    <button type="button" className="block w-full" onClick={onOpen} data-testid="pay-item-open">
      {content}
    </button>
  );
}

export function PayItemDialog({ item, kind, onClose }: { item: PayItem | null; kind: PayItem["kind"]; onClose: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const [draft, setDraft] = useState<ItemDraft>(() => (item ? itemDraftFrom(item) : emptyItemDraft(kind)));
  const [checked, setChecked] = useState(false);
  const [advanced, setAdvanced] = useState(Boolean(item && item.amount_basis === "net"));

  const done = async () => {
    await queryClient.invalidateQueries({ queryKey: coachPayKeys.items });
    onClose();
  };
  const save = useMutation({
    mutationFn: () => {
      const body = itemBody(draft);
      if (!item) return createPayItem(token, body);
      const { kind: _kind, ...update } = body;
      return updatePayItem(token, item.id, update);
    },
    onSuccess: done,
  });
  const archive = useMutation({ mutationFn: () => archivePayItem(token, item!.id), onSuccess: done });

  const errors = checked ? itemErrors(draft) : {};
  const serverFields = save.error instanceof ApiError ? (save.error.payload.errors ?? {}) : {};
  const apiKey: Record<ItemField, string> = { name: "name", amount: "amount_cents", threshold: "weekly_threshold", roles: "roles" };
  const message = (field: ItemField) => (errors[field] ? t(errors[field]!) : apiKey[field] in serverFields ? localizeError(save.error, ui) : null);
  const formError = save.error && Object.keys(serverFields).length === 0 ? localizeError(save.error, ui) : archive.error ? localizeError(archive.error, ui) : null;
  const update = (patch: Partial<ItemDraft>) => setDraft({ ...draft, ...patch });
  const overtime = draft.kind === "overtime";

  return (
    <Dialog
      onClose={onClose}
      title={item ? t(`editItem_${draft.kind}`) : t(`addItem_${draft.kind}`)}
      size="md"
      variant="center"
      dismissible={!save.isPending}
      testId="pay-item-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (Object.keys(itemErrors(draft)).length > 0) return;
        save.mutate();
      }}
      error={formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
      footer={
        <div className="flex w-full flex-wrap items-center justify-between gap-2">
          {item ? (
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--danger)" }} disabled={archive.isPending} onClick={() => archive.mutate()} data-testid="pay-item-archive">
              {t("archiveItem")}
            </button>
          ) : (
            <span />
          )}
          <div className="flex items-center gap-2">
            <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
            <DialogButton type="submit" tone="primary" disabled={save.isPending} testId="pay-item-save">
              {t("saveItem")}
            </DialogButton>
          </div>
        </div>
      }
    >
      <div className="space-y-4">
        <FormRow label={t("itemName")} htmlFor={`${ids}-name`} error={message("name")} errorId={`${ids}-name-error`}>
          <input
            id={`${ids}-name`}
            className={controlClass}
            style={{ ...controlStyle, border: fieldBorder(message("name")) }}
            maxLength={120}
            placeholder={t(`itemNamePlaceholder_${draft.kind}`)}
            value={draft.name}
            onChange={(event) => update({ name: event.target.value })}
            {...invalidFieldProps(message("name"), `${ids}-name-error`)}
          />
        </FormRow>
        <FormRow
          label={overtime ? t("ratePerHour") : t("amount")}
          htmlFor={`${ids}-amount`}
          error={message("amount")}
          errorId={`${ids}-amount-error`}
        >
          <input
            id={`${ids}-amount`}
            inputMode="decimal"
            className={controlClass + " max-w-[10rem]"}
            style={{ ...controlStyle, border: fieldBorder(message("amount")) }}
            value={draft.amount}
            onChange={(event) => update({ amount: event.target.value })}
            {...invalidFieldProps(message("amount"), `${ids}-amount-error`)}
          />
        </FormRow>
        {overtime ? (
          <FormRow label={t("weeklyThreshold")} htmlFor={`${ids}-threshold`} hint={t("weeklyThresholdHint")} error={message("threshold")} errorId={`${ids}-threshold-error`}>
            <input
              id={`${ids}-threshold`}
              inputMode="numeric"
              className={controlClass + " max-w-[8rem]"}
              style={{ ...controlStyle, border: fieldBorder(message("threshold")) }}
              value={draft.threshold}
              onChange={(event) => update({ threshold: event.target.value })}
              {...invalidFieldProps(message("threshold"), `${ids}-threshold-error`)}
            />
          </FormRow>
        ) : (
          <FormRow label={t("unit")}>
            <Choice
              label={t("unit")}
              value={draft.unit}
              onChange={(unit) => update({ unit })}
              options={(["per_period", "per_occurrence"] as const).map((unit) => ({ value: unit, label: t(`unit_${unit}`) }))}
              testId="pay-item-unit"
            />
          </FormRow>
        )}
        <FormRow label={t("forRoles")} error={message("roles")} errorId={`${ids}-roles-error`}>
          <Chips
            label={t("forRoles")}
            invalid={Boolean(message("roles"))}
            value={draft.roles}
            onChange={(roles) => update({ roles })}
            options={PAY_ROLES.map((role) => ({ value: role, label: t(`role_${role}`) }))}
          />
        </FormRow>
        <Advanced open={advanced} onToggle={() => setAdvanced((value) => !value)}>
          <FormRow label={t("basis")} hint={t("basisHint")}>
            <Choice label={t("basis")} value={draft.basis} onChange={(basis) => update({ basis })} options={[{ value: "gross", label: t("gross") }, { value: "net", label: t("net") }]} testId="pay-item-basis" />
          </FormRow>
        </Advanced>
      </div>
    </Dialog>
  );
}
