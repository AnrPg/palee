"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchMyPackages, fetchPublicPackages, myPackagesKey, publicPackagesKey } from "@/api/my-payments";
import { useSession } from "@/components/session-provider";
import { nativePlatform } from "@/lib/platform";
import { FRESHNESS } from "@/lib/query-policy";

import { BuyPackageSheet } from "./BuyPackageSheet";
import { buyableHere, renewalPackages } from "./checkout-flow";
import { deskMode, deskPackages } from "./desk-payment";
import { DeskRenewDialog } from "./DeskPayment";

/**
 * What a box sells online that may be bought on this device (ADR-248,
 * ADR-256): nothing when the box takes no online payments, and never a
 * digital-only package inside the store apps. ADR-291: a box without online
 * payments lists `deskPackages` instead, asked for in the app and paid at the
 * front desk (no store rule applies: nothing is paid in the app).
 */
export function useBoxSales(slug: string | null | undefined) {
  // ADR-553: the box chooses who sees its packages; signed in, the API
  // answers for this person (their own, people always or never shown).
  const { status } = useSession();
  const signedIn = status === "authenticated";
  const query = useQuery({
    queryKey: signedIn ? myPackagesKey(slug ?? "none") : publicPackagesKey(slug ?? "none"),
    enabled: Boolean(slug) && status !== "loading",
    queryFn: () => (signedIn ? fetchMyPackages(slug!) : fetchPublicPackages(slug!)),
    staleTime: FRESHNESS.reference,
    retry: false,
  });
  const data = query.data;
  const packages = data?.online_payments ? buyableHere(data.packages, nativePlatform()) : [];
  return {
    packages,
    desk: deskMode(data),
    deskPackages: deskPackages(data),
    provider: data?.provider ?? null,
    /** How many packages the box shows this person (none: ask the box). */
    shownCount: data?.packages?.length ?? null,
    /** The box shows this person only their own packages (ADR-553). */
    ownOnly: Boolean(data?.own_only),
    /** The names of the person's own packages among those shown. */
    heldNames: (data?.packages ?? []).filter((item) => item.held).map((item) => item.name),
    isLoading: query.isLoading || status === "loading",
  };
}

/** Box › «Συνδρομή» › «Ανανέωση» (mockup s4 option B, sheet 1). */
export function RenewButton({ slug }: { slug: string }) {
  const t = useTranslations("Pay");
  const sales = useBoxSales(slug);
  const packages = sales.desk ? sales.deskPackages : sales.packages;
  const [open, setOpen] = useState(false);
  if (renewalPackages(packages).length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-11 flex-auto items-center justify-center gap-2 whitespace-nowrap rounded-2xl px-4 text-center text-sm font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="pay-renew"
      >
        {t("renew")}
      </button>
      {open && sales.desk ? (
        <DeskRenewDialog slug={slug} packages={packages} onClose={() => setOpen(false)} />
      ) : open ? (
        <BuyPackageSheet slug={slug} packages={packages} mode={{ kind: "renew" }} origin="box" onClose={() => setOpen(false)} />
      ) : null}
    </>
  );
}
