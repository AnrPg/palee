"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";

import { listAdminLocations } from "@/api/facility";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { boxFindableByPlace } from "./box-on-map";

/**
 * Αρχική (staff admins): «Το box σου δεν φαίνεται στο Γύρω μου» while no
 * live branch has an address town or a map pin (ADR-583 Ε4 A). Hidden once
 * one has.
 */
export function BoxOnMapCard() {
  const t = useTranslations("BoxOnMap");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const locations = useQuery({
    queryKey: ["admin", "locations"],
    queryFn: () => listAdminLocations(token!),
    enabled: Boolean(token),
  });

  if (!locations.data || boxFindableByPlace(locations.data)) return null;

  return (
    <section
      aria-labelledby="box-on-map-card"
      data-testid="box-on-map-card"
      className="flex flex-wrap items-center gap-4 rounded-[2.2rem] p-6"
      style={{ background: "var(--panel)", border: "1px dashed var(--warning)" }}
    >
      <div className="min-w-0 flex-1">
        <h2 id="box-on-map-card" className="text-lg font-semibold" style={{ color: "var(--text)" }}>
          {t("title")}
        </h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("body")}</p>
      </div>
      <Link
        href={adminHref("/admin/settings/locations", slug)}
        className="inline-flex min-h-10 items-center rounded-full px-5 text-sm font-semibold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {t("action")}
      </Link>
    </section>
  );
}
