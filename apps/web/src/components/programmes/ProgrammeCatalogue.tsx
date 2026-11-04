"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchProgrammeCatalogue, type CatalogueFilters, type ProgrammeGoal, type ProgrammeLevel } from "@/api/programmes";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { FRESHNESS } from "@/lib/query-policy";

import { ProgrammeTile } from "./ProgrammeTile";

type Chip = "all" | "strength" | "endurance" | "beginner";

const CHIP_FILTERS: Record<Chip, Pick<CatalogueFilters, "goal" | "level">> = {
  all: {},
  strength: { goal: "strength" as ProgrammeGoal },
  endurance: { goal: "endurance" as ProgrammeGoal },
  beginner: { level: "beginner" as ProgrammeLevel },
};

/**
 * «Αγορά προγραμμάτων» (ADR-370, mockup W8 s3 A): cards with chips on top;
 * search is an icon that opens a field. Only programmes their box lists in
 * the catalogue appear here.
 */
export function ProgrammeCatalogue() {
  const t = useTranslations("Programmes");
  const [chip, setChip] = useState<Chip>("all");
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");
  const filters: CatalogueFilters = { ...CHIP_FILTERS[chip], query };
  const catalogue = useQuery({
    queryKey: ["public", "programmes", chip, query.trim()],
    queryFn: () => fetchProgrammeCatalogue(filters),
    staleTime: FRESHNESS.reference,
  });
  const list = Array.isArray(catalogue.data) ? catalogue.data.filter((entry) => entry && typeof entry.id === "string") : [];
  const chips: { value: Chip; label: string }[] = [
    { value: "all", label: t("chip.all") },
    { value: "strength", label: t("goal.strength") },
    { value: "endurance", label: t("goal.endurance") },
    { value: "beginner", label: t("chip.beginner") },
  ];

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col gap-4 px-4 pb-10 pt-6" data-testid="programme-catalogue">
      <header className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("storeTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("storeLead")}</p>
        </div>
        <button
          type="button"
          aria-label={t("search")}
          aria-expanded={searching}
          onClick={() => setSearching((value) => !value)}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="programme-search-toggle"
        >
          <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
        </button>
      </header>
      {searching ? (
        <input
          autoFocus
          className="w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
          value={query}
          maxLength={60}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("searchPlaceholder")}
          aria-label={t("search")}
          data-testid="programme-search"
        />
      ) : null}
      <SegmentPicker<Chip> options={chips} value={chip} onChange={setChip} ariaLabel={t("storeTitle")} semantics="radiogroup" />

      {catalogue.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {catalogue.isError ? <ErrorNotice>{t("loadFailed")}</ErrorNotice> : null}
      {!catalogue.isLoading && !catalogue.isError && list.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("storeEmpty")}</p> : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {list.map((programme) => (
          <ProgrammeTile
            key={programme.id}
            programme={programme}
            href={`/b/${encodeURIComponent(programme.organization_slug)}/programmes/${encodeURIComponent(programme.id)}`}
            testId={`programme-card-${programme.id}`}
          />
        ))}
      </div>
    </main>
  );
}
