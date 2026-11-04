"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useId, useState, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import { archivePayItem, coachPayKeys, createPayItem, fetchPayItems, updatePayItem, type PayItem } from "@/api/coach-pay";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";
import { SPARK_CREATE_STYLE } from "@/lib/spark";

import { ITEM_FREQUENCIES, PAY_ROLES, emptyItemDraft, itemBody, itemDraftFrom, itemErrors, itemMode, type ItemDraft, type ItemField, type ItemMode, withoutKey } from "./coach-pay";
import { OneOffLineForm } from "./OneOffLineForm";
import { Advanced, Chips, Choice, FormRow, NetMark, controlClass, controlStyle, useMoney } from "./pay-ui";

type Kind = PayItem["kind"];

/**
 * «Υπερωρίες και επιδόματα» (ADR-382, ADR-510; ANR 2026-11-04, mockup B):
 * the box's overtime and allowances. Each is either added by every
 * calculation («Κάθε περίοδο») or added by hand to one person's open period
 * («Μία φορά»). An info box says what a pay period is and where it is set.
 * The same list lives in Settings (only «Κάθε περίοδο»: it is a setting)
 * and in Οικονομικά › Αμοιβές coaches. Items are archived, never deleted.
 */
export function PayItemsCatalog({ canEdit, canAddOneOff = false, onOpenPeriods }: { canEdit: boolean; canAddOneOff?: boolean; onOpenPeriods?: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const [editing, setEditing] = useState<{ item: PayItem | null; kind: Kind } | null>(null);
  const [added, setAdded] = useState<string | null>(null);
  const query = useQuery({ queryKey: coachPayKeys.items, enabled: Boolean(token), queryFn: () => fetchPayItems(token) });

  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;
  const items = (query.data?.items ?? []).filter((item) => !item.archived_at);
  const canAdd = canEdit || canAddOneOff;

  return (
    <section className="space-y-4" data-testid="pay-items">
      <HowItWorks onOpenPeriods={onOpenPeriods} />
      {added ? (
        <p className="flex flex-wrap items-center gap-2 rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text)" }} role="status" data-testid="pay-item-added">
          <span className="min-w-0 flex-1">{added}</span>
          {onOpenPeriods ? (
            <button type="button" className="font-semibold" style={{ color: "var(--primary)" }} onClick={onOpenPeriods}>
              {t("openPeriods")}
            </button>
          ) : null}
        </p>
      ) : null}
      {(["overtime", "allowance"] as const).map((kind) => {
        const list = items.filter((item) => item.kind === kind);
        return (
          <div key={kind} className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
              <h4 className="flex-1 font-semibold" style={{ color: "var(--text)" }}>{t(`items_${kind}`)}</h4>
              {canAdd ? (
                <button
                  type="button"
                  className="rounded-full px-3 py-1.5 text-sm font-semibold"
                  style={SPARK_CREATE_STYLE}
                  onClick={() => {
                    setAdded(null);
                    setEditing({ item: null, kind });
                  }}
                  data-testid={`pay-add-item-${kind}`}
                >
                  + {t(`kind_${kind}`)}
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
      {editing ? (
        <PayItemDialog
          item={editing.item}
          kind={editing.kind}
          modes={editing.item ? [itemMode(editing.item)] : [...(canEdit ? (["recurring"] as const) : []), ...(canAddOneOff ? (["oneOff"] as const) : [])]}
          canSaveRates={canEdit}
          onAdded={setAdded}
          onClose={() => setEditing(null)}
        />
      ) : null}
    </section>
  );
}

/** ANR 2026-11-04: what «Κάθε περίοδο» and «Μία φορά» do, and what a pay period is and where it is set. */
function HowItWorks({ onOpenPeriods }: { onOpenPeriods?: () => void }) {
  const t = useTranslations("CoachPay");
  return (
    <aside className="space-y-2 rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--info) 8%, var(--panel))", border: "1px solid color-mix(in srgb, var(--info) 30%, var(--border))", color: "var(--text-soft)" }} data-testid="pay-items-info">
      <p className="font-semibold" style={{ color: "var(--text)" }}>{t("howItWorks")}</p>
      <p>
        <strong style={{ color: "var(--text)" }}>{t("mode_recurring")}:</strong> {t("howRecurring")}
      </p>
      <p>
        <strong style={{ color: "var(--text)" }}>{t("mode_oneOff")}:</strong> {t("howOneOff")}
      </p>
      <p>
        <strong style={{ color: "var(--text)" }}>{t("whatIsPeriod")}</strong> {t("periodExplained")}{" "}
        {onOpenPeriods ? (
          <button type="button" className="font-semibold" style={{ color: "var(--primary)" }} onClick={onOpenPeriods} data-testid="pay-items-open-periods">
            {t("openPeriods")}
          </button>
        ) : (
          <Link href="/admin/finance?tab=pay&pay_view=periods" className="font-semibold" style={{ color: "var(--primary)" }}>
            {t("openPeriods")}
          </Link>
        )}
      </p>
    </aside>
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
          {item.kind === "overtime"
            ? item.weekly_threshold == null
              ? t("summaryOvertimeOneOff")
              : t("summaryOvertimeRecurring", { hours: item.weekly_threshold })
            : itemMode(item) === "recurring"
              ? t("summaryAllowanceRecurring", { frequency: t(`itemFrequency_${item.frequency ?? "period"}`) })
              : t("summaryAllowanceOneOff")}
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

/**
 * Adds or changes overtime or an allowance. A new one starts with the
 * «Κάθε περίοδο · Μία φορά» switch (mockup B): «Κάθε περίοδο» saves an item
 * every calculation pays; «Μία φορά» adds a line to one person's open
 * period. An existing item keeps its workflow.
 */
export function PayItemDialog({
  item,
  kind,
  modes,
  canSaveRates,
  onAdded,
  onClose,
}: {
  item: PayItem | null;
  kind: Kind;
  modes: ItemMode[];
  canSaveRates: boolean;
  onAdded?: (message: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("CoachPay");
  const [mode, setMode] = useState<ItemMode>(modes[0] ?? "recurring");
  const title = item ? t(`editItem_${kind}_${itemMode(item)}`) : t(`newItem_${kind}`);
  const switcher =
    !item && modes.length > 1 ? (
      <ModeSwitch kind={kind} value={mode} onChange={setMode} />
    ) : null;

  if (!item && mode === "oneOff") {
    return <OneOffLineForm kind={kind} title={title} header={switcher} canSaveRates={canSaveRates} onAdded={onAdded} onClose={onClose} />;
  }
  return <ItemForm item={item} kind={kind} mode={item ? itemMode(item) : mode} title={title} header={switcher} onClose={onClose} />;
}

/** «Κάθε περίοδο · Μία φορά» with what each does (ANR 2026-11-04). */
export function ModeSwitch({ kind, value, onChange }: { kind: Kind; value: ItemMode; onChange: (mode: ItemMode) => void }) {
  const t = useTranslations("CoachPay");
  return (
    <div role="radiogroup" aria-label={t("howOften")} className="grid grid-cols-2 gap-1 rounded-xl p-1" style={{ background: "var(--panel-muted)" }} data-testid="pay-item-mode">
      {(["recurring", "oneOff"] as const).map((mode) => {
        const on = mode === value;
        return (
          <button
            key={mode}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(mode)}
            className="rounded-lg px-2 py-2 text-sm font-bold leading-tight"
            style={on ? { background: "var(--text)", color: "var(--bg)" } : { background: "transparent", color: "var(--text-soft)" }}
            data-mode={mode}
          >
            {t(`mode_${mode}`)}
            <span className="block text-xs font-medium" style={{ opacity: on ? 0.8 : 1, color: on ? "inherit" : "var(--dim)" }}>
              {t(`modeHint_${mode}_${kind}`)}
            </span>
          </button>
        );
      })}
    </div>
  );
}

function ItemForm({ item, kind, mode, title, header, onClose }: { item: PayItem | null; kind: Kind; mode: ItemMode; title: string; header: ReactNode; onClose: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const [draft, setDraft] = useState<ItemDraft>(() => (item ? itemDraftFrom(item) : emptyItemDraft(kind, mode)));
  const [checked, setChecked] = useState(false);
  const [advanced, setAdvanced] = useState(Boolean(item && item.amount_basis === "net"));
  // The switch above the form changes the workflow of a new item.
  const current = { ...draft, mode };

  const done = async () => {
    await queryClient.invalidateQueries({ queryKey: coachPayKeys.items });
    onClose();
  };
  const save = useMutation({
    mutationFn: () => {
      const body = itemBody(current);
      if (!item) return createPayItem(token, body);
      return updatePayItem(token, item.id, withoutKey(body, "kind"));
    },
    onSuccess: done,
  });
  const archive = useMutation({ mutationFn: () => archivePayItem(token, item!.id), onSuccess: done });

  const errors = checked ? itemErrors(current) : {};
  const serverFields = save.error instanceof ApiError ? (save.error.payload.errors ?? {}) : {};
  const apiKey: Record<ItemField, string> = { name: "name", amount: "amount_cents", threshold: "weekly_threshold", roles: "roles" };
  const message = (field: ItemField) => (errors[field] ? t(errors[field]!) : apiKey[field] in serverFields ? localizeError(save.error, ui) : null);
  const formError = save.error && Object.keys(serverFields).length === 0 ? localizeError(save.error, ui) : archive.error ? localizeError(archive.error, ui) : null;
  const update = (patch: Partial<ItemDraft>) => setDraft({ ...draft, ...patch });
  const overtime = kind === "overtime";
  const recurring = mode === "recurring";

  return (
    <Dialog
      onClose={onClose}
      title={title}
      size="md"
      variant="center"
      dismissible={!save.isPending}
      testId="pay-item-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (Object.keys(itemErrors(current)).length > 0) return;
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
        {header}
        <p className="rounded-xl px-3 py-2 text-xs" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="pay-item-explain">
          {t(`explain_${kind}_${mode}`)}
        </p>
        <FormRow label={t("itemName")} htmlFor={`${ids}-name`} error={message("name")} errorId={`${ids}-name-error`}>
          <input
            id={`${ids}-name`}
            className={controlClass}
            style={{ ...controlStyle, border: fieldBorder(message("name")) }}
            maxLength={120}
            placeholder={t(`itemNamePlaceholder_${kind}`)}
            value={draft.name}
            onChange={(event) => update({ name: event.target.value })}
            {...invalidFieldProps(message("name"), `${ids}-name-error`)}
          />
        </FormRow>
        <FormRow
          label={overtime ? t("ratePerHour") : recurring ? t("amountEach") : t("amountPerTime")}
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
        {overtime && recurring ? (
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
        ) : null}
        {!overtime && recurring ? (
          <FormRow label={t("howOften")} hint={t(`itemFrequencyHint_${draft.frequency}`)}>
            <Choice
              label={t("howOften")}
              value={draft.frequency}
              onChange={(frequency) => update({ frequency })}
              options={ITEM_FREQUENCIES.map((frequency) => ({ value: frequency, label: t(`itemFrequency_${frequency}`) }))}
              testId="pay-item-frequency"
            />
          </FormRow>
        ) : null}
        <FormRow label={t("forRoles")} hint={recurring ? t("forRolesHint") : undefined} error={message("roles")} errorId={`${ids}-roles-error`}>
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
