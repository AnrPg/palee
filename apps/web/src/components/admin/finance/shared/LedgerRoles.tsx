"use client";

import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import type { FinanceRecord } from "@/api/finance";
import {
  changeClientRoles,
  previewClientRoles,
  type ClientRolesChange,
  type ClientRolesResult,
  type RoleName,
} from "@/api/roles";
import { useSession } from "@/components/session-provider";
import { RoleLabel } from "@/components/semantic-label";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Popover } from "@/components/ui/Popover";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatDateKey } from "@/lib/local-date";
import { localizeError, roleLabel } from "@/i18n/presentation";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can, membershipRoles } from "@/lib/role-navigation";
import { editableRoles, grantableRoles } from "@/lib/role-hierarchy";
import {
  BUYER_ROLES,
  LEDGER_ROLE_ORDER,
  STAFF_ROLES,
  memberRoles,
  orderedRoles as ordered,
} from "@/components/admin/finance/shared/ledger-roles";

// ADR-812: the finance ledger shows every role a client holds in the box and
// lets whoever may change roles (owner, admin) change them, one person from
// the column or many at once. The server keeps the finance profile in step.

/** Whether the signed-in person may change roles from the ledger (γ: else view only). */
export function useLedgerRoleRights() {
  const { membership: actor } = useSelectedMembershipRole();
  const { currentUser } = useSession();
  const actorRoles = membershipRoles(actor);
  const canChange = can(actor, "grant_staff_roles") && grantableRoles(actorRoles).length > 0;
  return { actorRoles, canChange, selfId: currentUser?.id ?? null };
}

function chipStyle(role: string) {
  if (role === "athlete") return { background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)", border: "1px solid transparent" };
  if (role === "member") return { background: "color-mix(in srgb, var(--muted) 14%, transparent)", color: "var(--text-soft)", border: "1px solid transparent" };
  if (role === "guest") return { background: "transparent", color: "var(--muted)", border: "1px solid var(--border)" };
  return { background: "transparent", color: "var(--muted)", border: "1px dashed var(--border-strong)" };
}

export function RoleChips({ roles }: { roles: readonly string[] }) {
  return (
    <span className="inline-flex flex-wrap gap-1" data-testid="ledger-role-chips">
      {roles.map((role) => (
        <span
          key={role}
          data-role={role}
          className="rounded-full px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap"
          style={chipStyle(role)}
        >
          <RoleLabel role={role} />
        </span>
      ))}
    </span>
  );
}

function diff(current: readonly RoleName[], next: readonly RoleName[]) {
  return {
    add: next.filter((role) => !current.includes(role)),
    remove: current.filter((role) => !next.includes(role)),
  };
}

function refusedReason(code: string | undefined, i18n: ReturnType<typeof useUiTranslations>) {
  return localizeError(new ApiError(422, code ?? "validation_failed", { code: code ?? "validation_failed" }), i18n);
}

/** α and β: what the change does, said before «Αποθήκευση». */
function ImpactNotes({ results }: { results: ClientRolesResult[] }) {
  const t = useTranslations("LedgerRoles");
  const uiLocale = useUiLocale();
  const bookings = results.reduce((sum, result) => sum + (result.impact?.future_bookings ?? 0), 0);
  const kept = results.map((result) => result.impact?.kept_package).filter((pkg) => Boolean(pkg));
  if (bookings === 0 && kept.length === 0) return null;
  const single = results.length === 1;
  return (
    <div
      role="note"
      data-testid="ledger-roles-impact"
      className="space-y-1 rounded-xl px-3 py-2 text-xs"
      style={{ background: "color-mix(in srgb, var(--warning) 12%, var(--panel))", border: "1px solid var(--warning)", color: "var(--text)" }}
    >
      {bookings > 0 ? <p>{t(single ? "bookingsCancelled" : "bulkBookingsCancelled", { count: bookings })}</p> : null}
      {single && kept[0] ? (
        <p>{kept[0].ends_on ? t("packageKept", { name: kept[0].name ?? "", date: formatDateKey(uiLocale, kept[0].ends_on) ?? kept[0].ends_on }) : t("packageKeptOpen", { name: kept[0].name ?? "" })}</p>
      ) : null}
      {!single && kept.length > 0 ? <p>{t("bulkPackagesKept", { count: kept.length })}</p> : null}
    </div>
  );
}

function useInvalidateRoles() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "users"] }),
    ]);
}

/** The «Ρόλοι» cell: every role as a chip; a button opening the editor for those who may change roles. */
export function RolesCell({ member }: { member: FinanceRecord }) {
  const t = useTranslations("LedgerRoles");
  const { actorRoles, canChange, selfId } = useLedgerRoleRights();
  const roles = memberRoles(member);
  const userId = String(member.id ?? "");
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const editable = canChange ? editableRoles(actorRoles, roles, userId === selfId) : [];

  if (roles.length === 0) return <span className="text-xs" style={{ color: "var(--dim)" }}>—</span>;
  if (editable.length === 0) return <RoleChips roles={roles} />;

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-label={t("changeFor", { name: String(member.nickname ?? "") })}
        aria-expanded={open}
        data-testid="ledger-roles-button"
        className="inline-flex items-center gap-1 rounded-full text-start hover:opacity-80"
      >
        <RoleChips roles={roles} />
        <span aria-hidden className="text-[10px]" style={{ color: "var(--muted)" }}>▾</span>
      </button>
      {open ? (
        <RolesEditor
          anchorRef={anchorRef}
          userId={userId}
          name={String(member.nickname ?? "")}
          current={roles}
          editable={editable}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

function RolesEditor({
  anchorRef,
  userId,
  name,
  current,
  editable,
  onClose,
}: {
  anchorRef: React.RefObject<HTMLButtonElement | null>;
  userId: string;
  name: string;
  current: RoleName[];
  editable: RoleName[];
  onClose: () => void;
}) {
  const t = useTranslations("LedgerRoles");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const invalidate = useInvalidateRoles();
  const [draft, setDraft] = useState<RoleName[]>(current);
  const visible = LEDGER_ROLE_ORDER.filter((role) => editable.includes(role) || current.includes(role));
  const { add, remove } = diff(current, draft);
  const changed = add.length + remove.length > 0;
  const keepsClient = draft.some((role) => BUYER_ROLES.includes(role));
  const change: ClientRolesChange = { user_ids: [userId], add, remove };

  const preview = useQuery({
    queryKey: ["admin", "roles-preview", userId, add.join(), remove.join()],
    enabled: Boolean(token) && changed && keepsClient,
    queryFn: () => previewClientRoles(token, change),
  });

  const save = useMutation({
    mutationFn: () => changeClientRoles(token, change),
    onSuccess: async (results) => {
      if (results.every((result) => result.status !== "refused")) {
        await invalidate();
        onClose();
      }
    },
  });
  const refused = save.data?.find((result) => result.status === "refused");

  const toggle = (role: RoleName) =>
    setDraft((roles) => ordered(roles.includes(role) ? roles.filter((item) => item !== role) : [...roles, role]));

  return (
    <Popover
      anchorRef={anchorRef}
      open
      onClose={onClose}
      width={300}
      role="dialog"
      ariaLabel={t("title", { name })}
      className="space-y-3 rounded-xl p-3 text-sm shadow-xl"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow-md)" }}
    >
      <p className="font-semibold" style={{ color: "var(--text)" }}>{t("title", { name })}</p>
      <div className="space-y-1.5" data-testid="ledger-roles-options">
        {visible.map((role) => {
          const selected = draft.includes(role);
          const locked = !editable.includes(role);
          return (
            <button
              key={role}
              type="button"
              aria-pressed={selected}
              disabled={locked || save.isPending}
              onClick={() => toggle(role)}
              data-role={role}
              className="flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-start disabled:opacity-60"
              style={{
                border: `1px ${STAFF_ROLES.includes(role) ? "dashed" : "solid"} ${selected ? "var(--primary)" : "var(--border)"}`,
                background: selected ? "color-mix(in srgb, var(--primary) 8%, var(--panel))" : "transparent",
              }}
            >
              <span
                aria-hidden
                className="mt-0.5 inline-block h-4 w-4 flex-none rounded"
                style={{ border: `2px solid ${selected ? "var(--primary)" : "var(--muted)"}`, background: selected ? "var(--primary)" : "transparent" }}
              />
              <span>
                <span className="block" style={{ color: "var(--text)" }}><RoleLabel role={role} /></span>
                {BUYER_ROLES.includes(role) ? (
                  <span className="block text-[11px]" style={{ color: "var(--dim)" }}>{t(`hint_${role}`)}</span>
                ) : null}
              </span>
            </button>
          );
        })}
      </div>

      {!keepsClient ? <ErrorNotice variant="field">{t("clientRoleRequired")}</ErrorNotice> : null}
      {keepsClient && add.some((role) => STAFF_ROLES.includes(role)) ? (
        <p className="text-xs" role="note" data-testid="role-grant-notice" style={{ color: "var(--warning)" }}>
          {i18n("roleGrantNotice")}
        </p>
      ) : null}
      {preview.data ? <ImpactNotes results={preview.data} /> : null}
      {refused ? <ErrorNotice variant="field">{refusedReason(refused.code, i18n)}</ErrorNotice> : null}
      {save.error ? <ErrorNotice variant="field">{localizeError(save.error, i18n)}</ErrorNotice> : null}

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => save.mutate()}
          disabled={!changed || !keepsClient || save.isPending || preview.isFetching}
          className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="ledger-roles-save"
        >
          {save.isPending ? t("saving") : t("save")}
        </button>
        <button type="button" onClick={onClose} className="rounded-full px-4 py-2 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text)" }}>
          {t("cancel")}
        </button>
      </div>
    </Popover>
  );
}

type Choice = "keep" | "add" | "remove";

/** C: one change of roles for every selected client; each keeps the roles it does not name. */
export function BulkRolesDialog({
  members,
  onClose,
  onDone,
}: {
  members: FinanceRecord[];
  onClose: () => void;
  onDone: () => void;
}) {
  const t = useTranslations("LedgerRoles");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const invalidate = useInvalidateRoles();
  const { actorRoles } = useLedgerRoleRights();
  const roles = LEDGER_ROLE_ORDER.filter((role) => grantableRoles(actorRoles).includes(role));
  const [choices, setChoices] = useState<Partial<Record<RoleName, Choice>>>({});
  const add = roles.filter((role) => choices[role] === "add");
  const remove = roles.filter((role) => choices[role] === "remove");
  const userIds = members.map((member) => String(member.id ?? ""));
  const names = new Map(members.map((member) => [String(member.id ?? ""), String(member.nickname ?? "")]));
  const change: ClientRolesChange = { user_ids: userIds, add, remove };
  const changed = add.length + remove.length > 0;

  const preview = useQuery({
    queryKey: ["admin", "roles-preview", "bulk", userIds.join(), add.join(), remove.join()],
    enabled: Boolean(token) && changed,
    queryFn: () => previewClientRoles(token, change),
  });
  const apply = useMutation({
    mutationFn: () => changeClientRoles(token, change),
    onSuccess: async () => {
      await invalidate();
    },
  });

  const results = apply.data ?? preview.data ?? [];
  const refused = results.filter((result) => result.status === "refused");
  const willChange = (preview.data ?? []).filter((result) => result.status === "preview").length;
  const done = Boolean(apply.data);
  const changedCount = (apply.data ?? []).filter((result) => result.status === "changed").length;

  return (
    <Dialog
      onClose={done ? onDone : onClose}
      title={t("bulkTitle", { count: members.length })}
      description={t("bulkHelp")}
      size="md"
      dismissible={!apply.isPending}
      testId="ledger-bulk-roles"
      footer={
        done ? (
          <DialogButton tone="primary" onClick={onDone}>{t("close")}</DialogButton>
        ) : (
          <>
            <DialogButton onClick={onClose} disabled={apply.isPending}>{t("cancel")}</DialogButton>
            <DialogButton
              tone="primary"
              onClick={() => apply.mutate()}
              disabled={!changed || apply.isPending || preview.isFetching || willChange === 0}
              testId="ledger-bulk-apply"
            >
              {apply.isPending ? t("saving") : t("bulkApply", { count: willChange })}
            </DialogButton>
          </>
        )
      }
    >
      <div className="space-y-3">
        {done ? (
          <p className="text-sm font-semibold" data-testid="ledger-bulk-done" style={{ color: "var(--text)" }}>
            {t("bulkDone", { count: changedCount })}
          </p>
        ) : (
          <ul className="space-y-2">
            {roles.map((role) => (
              <li key={role} className="flex flex-wrap items-center justify-between gap-2">
                <span className="text-sm" style={{ color: "var(--text)" }}><RoleLabel role={role} /></span>
                <span className="inline-flex rounded-full p-0.5" role="radiogroup" aria-label={t("choiceFor", { role: roleLabel(role, i18n) })} style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  {(["keep", "add", "remove"] as Choice[]).map((choice) => {
                    const selected = (choices[role] ?? "keep") === choice;
                    return (
                      <button
                        key={choice}
                        type="button"
                        role="radio"
                        aria-checked={selected}
                        data-role={role}
                        data-choice={choice}
                        disabled={apply.isPending}
                        onClick={() => setChoices((current) => ({ ...current, [role]: choice }))}
                        className="rounded-full px-3 py-1 text-xs font-semibold"
                        style={selected ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { color: "var(--text-soft)" }}
                      >
                        {t(choice)}
                      </button>
                    );
                  })}
                </span>
              </li>
            ))}
          </ul>
        )}

        {!done && preview.data ? (
          <>
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("bulkWillChange", { count: willChange })}</p>
            <ImpactNotes results={preview.data} />
          </>
        ) : null}

        {refused.length > 0 ? (
          <div className="space-y-1 text-xs" data-testid="ledger-bulk-refused">
            <p className="font-semibold" style={{ color: "var(--text)" }}>{t(done ? "bulkRefused" : "bulkWillRefuse", { count: refused.length })}</p>
            <ul className="space-y-0.5" style={{ color: "var(--text-soft)" }}>
              {refused.map((result) => (
                <li key={result.user_id}>{t("refusedLine", { name: names.get(result.user_id) ?? "", reason: refusedReason(result.code, i18n) })}</li>
              ))}
            </ul>
          </div>
        ) : null}
        {preview.error ? <ErrorNotice variant="field">{localizeError(preview.error, i18n)}</ErrorNotice> : null}
        {apply.error ? <ErrorNotice variant="field">{localizeError(apply.error, i18n)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
