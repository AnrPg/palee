"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchFinanceMembers, retireFinancePackage, updateFinancePackage, type FinanceRecord } from "@/api/finance";
import { RoleLabel } from "@/components/semantic-label";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { holdersByRole, isAvailable, replacementCandidates } from "./package-availability";

/**
 * Mockup 2A (ANR 2026-11-28): «Διαθέσιμο» is a switch at the top of the
 * package, outside «Επεξεργασία». Withdrawing asks first and, when members
 * hold the package, moves them to another package in the same dialog (the
 * server retires and reassigns in one transaction). Turning it back on is
 * immediate. Staff without «Πακέτα» see the state only.
 */
export function PackageAvailabilityRow({
  token,
  pkg,
  packages,
  canManage,
}: {
  token: string;
  pkg: FinanceRecord;
  packages: FinanceRecord[];
  canManage: boolean;
}) {
  const t = useTranslations("PackageAvailability");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const packageId = String(pkg.id ?? "");
  const available = isAvailable(pkg);
  const [confirming, setConfirming] = useState(false);

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] }),
    ]);

  const restore = useMutation({
    mutationFn: () => updateFinancePackage(token, packageId, { active: true }),
    onSuccess: refresh,
  });
  const pending = restore.isPending;
  const shown = pending ? true : available;

  return (
    <>
      <div
        className="flex min-h-13 items-center gap-3 rounded-2xl px-4 py-2"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        data-testid="package-availability-row"
        data-available={shown}
      >
        <span className="min-w-0 flex-1">
          <span id={`availability-${packageId}`} className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
            {shown ? t("available") : t("retired")}
          </span>
          <span className="block text-xs" style={{ color: "var(--dim)" }}>{shown ? t("availableHint") : t("retiredHint")}</span>
        </span>
        {canManage ? (
          <button
            type="button"
            role="switch"
            aria-checked={shown}
            aria-labelledby={`availability-${packageId}`}
            disabled={pending}
            onClick={() => (shown ? setConfirming(true) : restore.mutate())}
            className="relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-60"
            style={{ background: shown ? "var(--success)" : "var(--control-bg)", border: `1px solid ${shown ? "var(--success)" : "var(--control-border)"}` }}
            data-testid="package-availability-switch"
          >
            <span
              aria-hidden="true"
              className="absolute top-0.5 size-5.5 rounded-full shadow transition-[inset-inline-start]"
              style={{ background: "var(--control-knob)", insetInlineStart: shown ? "1.375rem" : "0.125rem" }}
            />
          </button>
        ) : null}
      </div>
      {restore.error ? <ErrorNotice>{localizeError(restore.error, ui)}</ErrorNotice> : null}
      {confirming ? (
        <RetireDialog token={token} pkg={pkg} packages={packages} onClose={() => setConfirming(false)} onRetired={refresh} />
      ) : null}
    </>
  );
}

function RetireDialog({
  token,
  pkg,
  packages,
  onClose,
  onRetired,
}: {
  token: string;
  pkg: FinanceRecord;
  packages: FinanceRecord[];
  onClose: () => void;
  onRetired: () => Promise<unknown>;
}) {
  const t = useTranslations("PackageAvailability");
  const ui = useUiTranslations();
  const packageId = String(pkg.id ?? "");
  const name = String(pkg.name ?? pkg.code ?? "");
  const [replacements, setReplacements] = useState<Record<string, string>>({});

  const holdersQuery = useQuery({
    queryKey: ["admin", "finance", "package-retirement-impact", packageId],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceMembers(token, { limit: "5000" }),
  });
  const byRole = holdersByRole(holdersQuery.data?.members ?? [], packageId);
  const roles = Object.keys(byRole);
  const holders = roles.reduce((sum, role) => sum + byRole[role], 0);
  const candidates = replacementCandidates(packages, packageId);

  const retire = useMutation({
    mutationFn: () => retireFinancePackage(token, packageId, replacements),
    onSuccess: async () => {
      await onRetired();
      onClose();
    },
  });

  const ready = holdersQuery.isSuccess && roles.every((role) => Boolean(replacements[role])) && (roles.length === 0 || candidates.length > 0);

  return (
    <Dialog
      onClose={onClose}
      title={t("confirmTitle", { name })}
      titleId="package-retire-title"
      size="sm"
      variant="center"
      testId="package-retire-dialog"
      footer={
        <div className="flex w-full flex-wrap gap-3">
          <button
            type="button"
            className="min-h-11 rounded-full px-5 text-sm font-semibold disabled:opacity-40"
            style={{ background: "color-mix(in srgb, var(--danger) 12%, var(--panel))", color: "var(--danger)" }}
            disabled={!ready || retire.isPending}
            onClick={() => retire.mutate()}
            data-testid="package-retire-confirm"
          >
            {retire.isPending ? t("retiring") : t("confirm")}
          </button>
          <button type="button" className="min-h-11 rounded-full px-5 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={onClose}>
            {t("cancel")}
          </button>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("confirmBody")}</p>
        {holdersQuery.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("checking")}</p> : null}
        {holdersQuery.isError ? <ErrorNotice>{t("checkFailed")}</ErrorNotice> : null}
        {holders > 0 ? (
          <div className="flex flex-col gap-3" data-testid="package-retire-replacements">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("holders", { count: holders })}</p>
            {roles.map((role) => (
              <label key={role} className="flex flex-col gap-1">
                <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
                  <RoleLabel role={role} /> · {t("roleCount", { count: byRole[role] })}
                </span>
                <Select
                  className="min-h-11 w-full rounded-xl px-3 text-sm"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={replacements[role] ?? ""}
                  onValueChange={(value) => setReplacements((current) => ({ ...current, [role]: value }))}
                >
                  <option value="">{t("pickReplacement")}</option>
                  {candidates.map((candidate) => (
                    <option key={String(candidate.id)} value={String(candidate.id)}>
                      {String(candidate.name ?? candidate.code ?? "")}
                    </option>
                  ))}
                </Select>
              </label>
            ))}
            {candidates.length === 0 ? <ErrorNotice>{t("noReplacement")}</ErrorNotice> : null}
          </div>
        ) : null}
        {retire.error ? <ErrorNotice>{localizeError(retire.error, ui)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
