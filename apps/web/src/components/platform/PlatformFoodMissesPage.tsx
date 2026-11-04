"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { fetchBarcodeMisses } from "@/api/body-devices";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";

/**
 * «Barcode χωρίς προϊόν» (ADR-421): barcodes members scanned that no food
 * source had, per country, most scanned first, so the team sees which
 * products and markets are missing. The list holds no person.
 */
export function PlatformFoodMissesPage() {
  const t = useTranslations("PlatformFoodMisses");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [country, setCountry] = useState("");
  const misses = useQuery({
    queryKey: ["platform", "food-misses", country],
    queryFn: () => fetchBarcodeMisses(token!, country || null),
    enabled: Boolean(token),
  });
  const countries = useQuery({
    queryKey: ["platform", "food-misses", ""],
    queryFn: () => fetchBarcodeMisses(token!, null),
    enabled: Boolean(token),
  });
  const choices = useMemo(
    () => [...new Set((countries.data ?? []).map((miss) => miss.country).filter((code) => code !== ""))].sort(),
    [countries.data],
  );
  const forbidden = misses.error instanceof ApiError && misses.error.status === 403;
  const day = (iso: string) => new Date(`${iso}T00:00:00`).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      {choices.length > 0 ? (
        <label className="mt-6 flex items-center gap-3 text-sm font-semibold text-[var(--text)]">
          {t("country")}
          <Select value={country} onValueChange={setCountry} className="min-h-11">
            <option value="">{t("countryAll")}</option>
            {choices.map((code) => (
              <option key={code} value={code}>
                {code}
              </option>
            ))}
          </Select>
        </label>
      ) : null}

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {misses.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {misses.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {misses.data?.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("empty")}</p> : null}

      {misses.data?.length ? (
        <ul className="mt-6 flex flex-col divide-y divide-[var(--border)] border-y border-[var(--border)]" data-testid="food-misses">
          {misses.data.map((miss) => (
            <li key={`${miss.barcode}-${miss.country}`} className="flex flex-wrap items-center gap-3 py-3">
              <div className="mr-auto flex flex-col">
                <span className="font-mono font-semibold text-[var(--text)]">{miss.barcode}</span>
                <span className="text-sm text-[var(--text-soft)]">
                  {miss.country || t("noCountry")} · {t("seen", { first: day(miss.first_seen_on), last: day(miss.last_seen_on) })}
                </span>
              </div>
              <span className="text-sm font-semibold text-[var(--text)]">{t("scans", { count: miss.scans })}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </main>
  );
}
