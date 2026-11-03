"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import { fetchProgrammeCatalogue, type CatalogueFilters, type MarketplaceProgramme, type ProgrammeGoal, type ProgrammeLevel } from "@/api/programmes";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { programmeMoney, ratingLabel, useProgrammeLabels } from "./programme-ui";

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
    staleTime: 60_000,
  });
  const list = catalogue.data ?? [];
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
        {list.map((programme) => <ProgrammeCard key={programme.id} programme={programme} />)}
      </div>
    </main>
  );
}

function ProgrammeCard({ programme }: { programme: MarketplaceProgramme }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const labels = useProgrammeLabels();
  const rating = ratingLabel(locale, programme.rating_average, programme.rating_count);
  return (
    <article className="flex min-w-0 flex-col gap-2 rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={`programme-card-${programme.id}`}>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{[labels.goal(programme.goal), labels.level(programme.level)].filter(Boolean).join(" · ")}</p>
      <h2 className="break-words text-base font-bold" style={{ color: "var(--text)" }}>{programme.title}</h2>
      <p className="text-xs" style={{ color: "var(--text-soft)" }}>{programme.organization_name}</p>
      <p className="flex flex-wrap items-baseline gap-x-2 text-sm" style={{ color: "var(--text)" }}>
        <b className="tabular-nums">{programmeMoney(locale, programme.price_cents, programme.currency)}</b>
        <span style={{ color: "var(--muted)" }}>{t("weeksShort", { count: programme.weeks })}</span>
        <span style={{ color: "var(--muted)" }}>{rating ?? t("newBadge")}</span>
      </p>
      <Link
        href={`/b/${encodeURIComponent(programme.organization_slug)}/programmes/${encodeURIComponent(programme.id)}`}
        className="mt-auto flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        {t("seeProgramme")}
      </Link>
    </article>
  );
}
