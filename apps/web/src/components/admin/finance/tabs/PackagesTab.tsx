"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { fetchFinancePackages, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { PackagePanel } from "@/components/admin/finance/panels/PackagePanel";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { PackageWizard } from "@/components/admin/finance/packages/PackageWizard";
import { useT } from "@/components/admin/finance/packages/package-ui";
import { usePackageAuthoring } from "@/components/admin/finance/packages/use-package-authoring";
import { typeLabelKey, type PackageDraft } from "@/components/admin/finance/packages/package-catalog";
import { SPARK_ACTIVE_STYLE, SPARK_CREATE_STYLE } from "@/lib/spark";
import type { FacilityLocation } from "@/api/facility";
import { BranchCoverageBadge } from "@/components/admin/BranchFilter";
import type { LocationScope } from "@/lib/location-scope";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { SoldOnlineBadge } from "@/components/admin/finance/packages/SoldOnlineBadge";
import { BoxAudienceRow, PackageAudienceBadge, PackageAudienceSheet } from "@/components/admin/finance/packages/PackageAudience";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { salesPageHref, soldOnlineCount } from "@/components/admin/finance/packages/sold-online";
import { useOrganizationSlug } from "@/lib/organization-slug";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

/** The branches a package is valid at (`facility.location_ids`, empty = everywhere). */
export function packageCoverage(pkg: FinanceRecord): LocationScope {
  const fields = (pkg.fields ?? {}) as Record<string, unknown>;
  const ids = fields["facility.location_ids"];
  return Array.isArray(ids) && ids.length > 0 ? ids.map(String).sort() : "all";
}

/** `locationIds`: the page branch filter (ADR-186 §7); packages valid there or everywhere show. */
export function PackagesTab({ locationIds }: { locationIds?: string } = {}) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const router = useRouter();
  const searchParams = useSearchParams();

  const openPackageId = searchParams.get("package");
  const showNew = searchParams.get("new") === "true";

  const setParam = useCallback(
    (key: string, value: string | null) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value === null) params.delete(key);
      else params.set(key, value);
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages", ...(locationIds ? [locationIds] : [])],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token, locationIds),
  });

  const packages = packagesQuery.data?.packages ?? [];
  const activePackages = packages.filter((pkg) => pkg.active !== false);
  const inactivePackages = packages.filter((pkg) => pkg.active === false);
  const { catalog, classTypes, locations, error: catalogError } = usePackageAuthoring(token);
  const [duplicateDraft, setDuplicateDraft] = useState<PackageDraft | null>(null);
  const { membership } = useSelectedMembershipRole();
  const canManage = can(membership, "manage_packages");
  // Mockup 1A (ANR 2026-11-28): a package's eye opens its «Ποιος το βλέπει».
  const [audienceId, setAudienceId] = useState<string | null>(null);
  const audiencePackage = audienceId ? (packages.find((pkg) => field(pkg, "id") === audienceId) ?? null) : null;
  const availability = useTranslations("PackageAvailability");

  return (
    <div className="space-y-4">
      {/* Header row */}
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {availability("availableCount", { count: activePackages.length })}
        </p>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={SPARK_CREATE_STYLE}
          onClick={() => setParam("new", "true")}
          type="button"
        >
          {i18n("newPackage909820b")}
        </button>
      </div>

      {/* ADR-553: who sees the packages, on the box's Palee page and website alike. */}
      <BoxAudienceRow token={token} />

      {/* Package list */}
      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {packagesQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        ) : activePackages.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{availability("noneAvailable")}</p>
        ) : (
          <PackageRows packages={activePackages} locations={locations} onOpen={(id) => setParam("package", id)} onAudience={canManage ? setAudienceId : undefined} />
        )}
      </div>

      {activePackages.length > 0 ? <SoldOnlineSummary packages={activePackages} /> : null}

      {inactivePackages.length > 0 ? (
        <details className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {availability("retiredSection", { count: inactivePackages.length })}
          </summary>
          <div style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}>
            <PackageRows packages={inactivePackages} locations={locations} onOpen={(id) => setParam("package", id)} />
          </div>
        </details>
      ) : null}

      {audiencePackage ? <PackageAudienceSheet token={token} pkg={audiencePackage} onClose={() => setAudienceId(null)} /> : null}

      {/* Side panel: package detail */}
      {openPackageId ? (
        <PackagePanel
          packageId={openPackageId}
          packages={packages}
          onClose={() => setParam("package", null)}
          onDuplicate={(draft) => {
            setDuplicateDraft(draft);
            const params = new URLSearchParams(searchParams.toString());
            params.delete("package");
            params.set("new", "true");
            router.replace(`?${params.toString()}`, { scroll: false });
          }}
        />
      ) : null}

      {/* Side panel: new package wizard (ADR-096) */}
      {showNew ? (
        <SidePanel
          title={i18n("newMembershipPackagef93a8cb")}
          subtitle={i18n("packages0a99901")}
          onClose={() => { setDuplicateDraft(null); setParam("new", null); }}
          width="md:max-w-[680px]"
          bare
        >
          {catalog ? (
            <div className="flex min-h-0 flex-1 flex-col">
              <PackageWizard
                key={duplicateDraft ? "duplicate" : "new"}
                catalog={catalog}
                token={token}
                classTypes={classTypes}
                locations={locations}
                packages={packages}
                initialDraft={duplicateDraft ?? undefined}
                onClose={() => { setDuplicateDraft(null); setParam("new", null); }}
                onCreated={(created) => {
                  setDuplicateDraft(null);
                  const params = new URLSearchParams(searchParams.toString());
                  params.delete("new");
                  params.set("package", String(created.id));
                  router.replace(`?${params.toString()}`, { scroll: false });
                }}
              />
            </div>
          ) : (
            catalogError ? (
            <div className="px-6 py-6"><ErrorNotice>{i18n("pkgCatalogUnavailable")}</ErrorNotice></div>
          ) : (
            <p className="px-6 py-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
          )
          )}
        </SidePanel>
      ) : null}
    </div>
  );
}

function PackageRows({
  packages,
  locations,
  onOpen,
  onAudience,
}: {
  packages: FinanceRecord[];
  locations: FacilityLocation[] | null | undefined;
  onOpen: (id: string) => void;
  /** Staff with «Πακέτα»: the eye opens the package's «Ποιος το βλέπει». */
  onAudience?: (id: string) => void;
}) {
  const uiLocale = useUiLocale();
  const t = useT();
  const availability = useTranslations("PackageAvailability");
  // The whole row opens the package (its name is the keyboard button); the
  // eye is a button of its own and does not open the package.
  return packages.map((pkg, index) => (
    <div
      key={field(pkg, "id")}
      className="flex w-full cursor-pointer items-center justify-between gap-4 px-6 py-4 transition-opacity hover:opacity-80"
      style={{ borderBottom: index < packages.length - 1 ? "1px solid var(--border)" : "none" }}
      onClick={() => onOpen(field(pkg, "id"))}
      data-testid="package-row"
    >
      <button className="min-w-0 text-start" onClick={(event) => { event.stopPropagation(); onOpen(field(pkg, "id")); }} type="button">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {field(pkg, "name", field(pkg, "code"))}
        </p>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
          {t(typeLabelKey(field(pkg, "package_type", "membership")))} · {t(`pkgBilling_${field(pkg, "billing_period", "monthly")}`)}
        </p>
      </button>
      <div className="flex items-center gap-4">
        <BranchCoverageBadge target={packageCoverage(pkg)} locations={locations} />
        <SoldOnlineBadge pkg={pkg} />
        <PackageAudienceBadge pkg={pkg} onOpen={onAudience ? () => onAudience(field(pkg, "id")) : undefined} />
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {money(uiLocale, pkg.base_price_cents)}
        </span>
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={pkg.active === false ? { background: "var(--border)", color: "var(--dim)" } : SPARK_ACTIVE_STYLE}>
          {pkg.active === false ? availability("retired") : availability("available")}
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>→</span>
      </div>
    </div>
  ));
}

/** «Πωλούνται online: N από M · Δες τη Σελίδα πακέτων ›» under the list (ADR-271). */
function SoldOnlineSummary({ packages }: { packages: FinanceRecord[] }) {
  const t = useTranslations("SoldOnline");
  const slug = useOrganizationSlug();
  const { count, total } = soldOnlineCount(packages);
  const href = salesPageHref(slug);
  if (total === 0) return null;
  return (
    <p className="flex flex-wrap items-center gap-1 px-2 text-xs" style={{ color: "var(--dim)" }} data-testid="sold-online-summary">
      <span>{t("listCount", { count, total })}</span>
      {href ? (
        <>
          <span aria-hidden="true">·</span>
          <Link href={href} className="font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("viewSalesPage")} ›
          </Link>
        </>
      ) : null}
    </p>
  );
}
