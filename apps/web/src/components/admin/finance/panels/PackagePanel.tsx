"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchFinancePackage,
  previewFinancePackageTerms,
  updateFinancePackage,
  type FinanceRecord,
  type PackageTermsPreview,
  type TermsChoice,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { BasicsStep, IncludedStep } from "@/components/admin/finance/packages/PackageWizard";
import { AdvancedSettings, LockStrip, MemberPreview, PackageContractDetails, previewContext, useT } from "@/components/admin/finance/packages/package-ui";
import { usePackageAuthoring } from "@/components/admin/finance/packages/use-package-authoring";
import { SoldOnlineCard } from "@/components/admin/finance/packages/SoldOnlineCard";
import { FeaturedPackageCard, PackageAudienceRow } from "@/components/admin/finance/packages/PackageAudience";
import { PackageAvailabilityRow } from "@/components/admin/finance/packages/PackageAvailability";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { SoldOnlineBadge } from "@/components/admin/finance/packages/SoldOnlineBadge";
import { PackageTermsApplySheet } from "@/components/admin/finance/packages/PackageTermsApplySheet";
import {
  applyLocks,
  changedFields,
  draftFromPackage,
  draftIssues,
  findType,
  resetAll,
  toPackageRequest,
  typeLabelKey,
  wizardSteps,
  type PackageDraft,
} from "@/components/admin/finance/packages/package-catalog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

export function PackagePanel({
  packageId,
  packages,
  onClose,
  onDuplicate,
}: {
  packageId: string;
  packages: FinanceRecord[];
  onClose: () => void;
  onDuplicate: (draft: PackageDraft) => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const t = useT();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const canManage = can(membership, "manage_packages");

  const packageQuery = useQuery({
    queryKey: ["admin", "finance", "package", packageId],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackage(token, packageId),
  });

  const pkg = packageQuery.data?.package ?? null;
  const { catalog, classTypes, locations } = usePackageAuthoring(token);

  // Mockup 2A (ANR 2026-11-28): «Διαθέσιμο» lives at the top of the package,
  // outside editing, so editing never changes it.
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<PackageDraft | null>(null);
  const [attempted, setAttempted] = useState(false);
  // ADR-770: «Ισχύει και για τα ενεργά μέλη;» after «Αποθήκευση αλλαγών».
  const [termsPreview, setTermsPreview] = useState<PackageTermsPreview | null>(null);

  const type = catalog && draft ? findType(catalog, draft.packageType) : undefined;

  function startEdit() {
    if (!pkg || !catalog) return;
    setEditing(true);
    setDraft(draftFromPackage(catalog, pkg));
    setAttempted(false);
  }

  function cancelEdit() {
    setEditing(false);
    setDraft(null);
  }

  function setField(key: string, value: unknown) {
    setDraft((previous) => {
      if (!previous || !catalog) return previous;
      const current = findType(catalog, previous.packageType);
      const fields = { ...previous.fields, [key]: value };
      return { ...previous, fields: current ? applyLocks(current, fields) : fields };
    });
  }

  const updateMutation = useMutation({
    mutationFn: (termsChoice?: TermsChoice) => {
      if (!editing || !draft || !catalog) throw new Error(i18n("noForm2807394"));
      return updateFinancePackage(token, packageId, {
        ...toPackageRequest(catalog, draft),
        ...(termsChoice ? { terms_choice: termsChoice } : {}),
      });
    },
    onSuccess: async () => {
      setEditing(false);
      setDraft(null);
      setTermsPreview(null);
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
    },
  });

  // ADR-770: what the save would do to the members who hold the package;
  // the sheet opens only when a change would reach them.
  const termsPreviewMutation = useMutation({
    mutationFn: () => {
      if (!editing || !draft || !catalog) throw new Error(i18n("noForm2807394"));
      return previewFinancePackageTerms(token, packageId, toPackageRequest(catalog, draft));
    },
    onSuccess: ({ preview }) => {
      if (preview?.needs_choice) setTermsPreview(preview);
      else updateMutation.mutate(undefined);
    },
  });

  function saveChanges() {
    setAttempted(true);
    if (draft && draftIssues(draft).length > 0) return;
    termsPreviewMutation.mutate();
  }

  return (
    <SidePanel
      title={pkg ? field(pkg, "name", field(pkg, "code")) : i18n("package7431e3d")}
      subtitle={i18n("membershipPackage4602237")}
      onClose={onClose}
      width="md:max-w-[680px]"
      footer={
        editing ? (
          <div className="flex gap-3">
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={updateMutation.isPending || termsPreviewMutation.isPending}
              onClick={saveChanges}
              type="button"
            >
              {updateMutation.isPending || termsPreviewMutation.isPending ? i18n("checking820d600") : i18n("saveChanges179359b")}
            </button>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              onClick={cancelEdit}
              type="button"
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        ) : (
          <div className="flex flex-wrap gap-3">
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              disabled={!catalog}
              onClick={startEdit}
              type="button"
            >
              {i18n("editPackage77c0543")}
            </button>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ color: "var(--primary)" }}
              disabled={!catalog || !pkg}
              onClick={() => {
                if (!catalog || !pkg) return;
                const copy = draftFromPackage(catalog, pkg);
                onDuplicate({ ...copy, name: t("pkgCopyName", { name: copy.name }) });
              }}
              type="button"
            >
              {t("pkgDuplicate")}
            </button>
          </div>
        )
      }
    >
      {packageQuery.isLoading ? (
        <p style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      ) : !pkg ? (
        <p style={{ color: "var(--primary-strong)" }}>{i18n("packageNotFound764673f")}</p>
      ) : (
        <div className="space-y-6">
          {/* Mockup 1A + 2A (ANR 2026-11-28): the two things staff change most, first. */}
          <div className="space-y-2" data-testid="package-top-controls">
            <PackageAvailabilityRow token={token} pkg={pkg} packages={packages} canManage={canManage} />
            <PackageAudienceRow token={token} pkg={pkg} canManage={canManage} />
          </div>
      {editing && draft && catalog && type ? (
        <div className="space-y-6">
          <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", color: "var(--text-soft)" }}>
            {t("pkgEditSnapshotNotice")}
          </p>
          <div className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)" }}>
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_type")}: {t(typeLabelKey(draft.packageType))}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("pkgTypeChangeHint")}</span>
          </div>
          <section className="space-y-4">
            <h3 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_basics")}</h3>
            <BasicsStep draft={draft} catalog={catalog} attempted={attempted} issues={draftIssues(draft)} onChange={(next) => setDraft({ ...next, fields: applyLocks(type, next.fields) })} packages={packages} locale={uiLocale} />
          </section>
          {wizardSteps(draft.packageType).includes("included") ? (
            <section className="space-y-4">
              <h3 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_included")}</h3>
              <IncludedStep draft={draft} catalog={catalog} attempted={attempted} issues={draftIssues(draft)} onField={setField} classTypes={classTypes} />
            </section>
          ) : null}
          <details className="rounded-2xl" style={{ border: "1px solid var(--border)" }}>
            <summary className="cursor-pointer px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
              ⚙ {t("pkgAdvancedSettings")}{changedFields(catalog, draft).length > 0 ? ` · ${changedFields(catalog, draft).length}` : ""}
            </summary>
            <div className="space-y-4 px-4 pb-4">
              <SoldOnlineCard token={token} pkg={pkg} />
              <FeaturedPackageCard token={token} pkg={pkg} />
              <AdvancedSettings
                catalog={catalog}
                type={type}
                draft={draft}
                context={{ classTypes, packages, locations }}
                changedCount={changedFields(catalog, draft).length}
                onFieldChange={setField}
                onResetAll={() => setDraft(resetAll(catalog, draft))}
              />
            </div>
          </details>
          <MemberPreview draft={draft} classTypes={classTypes} compact {...previewContext(catalog, draft, packages)} />
          {updateMutation.error instanceof Error && (
            <ErrorNotice>{localizeError(updateMutation.error, i18n)}</ErrorNotice>
          )}
          {termsPreviewMutation.error instanceof Error && (
            <ErrorNotice>{localizeError(termsPreviewMutation.error, i18n)}</ErrorNotice>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          {catalog ? <MemberPreview draft={draftFromPackage(catalog, pkg)} classTypes={classTypes} {...previewContext(catalog, draftFromPackage(catalog, pkg), packages)} /> : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <Stat label={t("pkgStep_type")} value={t(typeLabelKey(field(pkg, "package_type", "membership")))} />
            <Stat label={i18n("codeadac693")} value={field(pkg, "code")} />
            <Stat label={i18n("billingPeriodda59f5a")} value={t(`pkgBilling_${field(pkg, "billing_period", "monthly")}`)} />
            <Stat label={i18n("basePrice708f3d8")} value={money(uiLocale, pkg.base_price_cents)} />
            <Stat label={t("pkgAdvancedSettings")} value={Array.isArray(pkg.changed_fields) && pkg.changed_fields.length > 0 ? t("pkgChangesFromSuggested", { count: pkg.changed_fields.length }) : t("pkgNoChangesFromSuggested")} />
          </div>
          {/* ADR-271: «Πωλείται online» lives in the package's advanced settings. */}
          <details className="rounded-2xl" style={{ border: "1px solid var(--border)" }} data-testid="package-advanced">
            <summary className="flex cursor-pointer items-center gap-2 px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
              <span className="flex-1">⚙ {t("pkgAdvancedSettings")}</span>
              <SoldOnlineBadge pkg={pkg} />
            </summary>
            <div className="space-y-4 px-4 pb-4">
              <SoldOnlineCard token={token} pkg={pkg} />
              <FeaturedPackageCard token={token} pkg={pkg} />
            </div>
          </details>
          {catalog ? <PackageContractDetails catalog={catalog} draft={draftFromPackage(catalog, pkg)} packages={packages} /> : null}
          {Array.isArray(pkg.tags) && (pkg.tags as string[]).length > 0 && (
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] mb-2" style={{ color: "var(--dim)" }}>{i18n("tags848eed0")}</p>
              <div className="flex flex-wrap gap-2">
                {(pkg.tags as string[]).map((tag) => (
                  <span key={tag} className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }}>{tag}</span>
                ))}
              </div>
            </div>
          )}
          {catalog && findType(catalog, field(pkg, "package_type", "membership")) ? (
            <div className="pt-6">
              <LockStrip type={findType(catalog, field(pkg, "package_type", "membership"))!} />
            </div>
          ) : null}
        </div>
      )}
        </div>
      )}
      {termsPreview ? (
        <PackageTermsApplySheet
          preview={termsPreview}
          classTypeNames={new Map(classTypes.map((classType) => [String(classType.id), String(classType.name)]))}
          saving={updateMutation.isPending}
          error={updateMutation.error ? <ErrorNotice>{localizeError(updateMutation.error, i18n)}</ErrorNotice> : null}
          onCancel={() => setTermsPreview(null)}
          onConfirm={(choice) => updateMutation.mutate(choice)}
        />
      ) : null}
    </SidePanel>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
      <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{value || "—"}</p>
    </div>
  );
}
