"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  decideExerciseCandidate,
  fetchExerciseCandidates,
  type ExerciseCandidateDecision,
  type ExerciseNameCandidate,
} from "@/api/exercise-suggestions";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Combobox, type ComboboxOption } from "@/components/ui/Combobox";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { rankItems } from "@/lib/structured-plan/fuzzy";

const STATUSES: ExerciseNameCandidate["status"][] = ["pending", "approved", "rejected"];
const CATEGORIES = ["strength", "bodyweight", "cardio", "mobility", "skill"] as const;
const MIN_OWNERS = [1, 2, 3, 5, 10];

type CatalogEntry = { catalog_slug: string; name: string; category?: string | null };

/**
 * «Ασκήσεις προς έλεγχο» (ADR-461): exercise names people and boxes typed
 * that matched no entry of the catalog the WOD editors use, most typed
 * first. The Palee team approves one as a new entry or as an alias of an
 * existing one, or rejects it; only approved names become «Palee»
 * suggestions. Every decision is audited. The list holds no person.
 */
export function PlatformExerciseCandidatesPage() {
  const t = useTranslations("PlatformExerciseCandidates");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [status, setStatus] = useState<ExerciseNameCandidate["status"]>("pending");
  const [minOwners, setMinOwners] = useState(2);
  const queue = useQuery({
    queryKey: ["platform", "exercise-candidates", status, minOwners],
    queryFn: () => fetchExerciseCandidates(token!, status, minOwners),
    enabled: Boolean(token),
  });
  const forbidden = queue.error instanceof ApiError && queue.error.status === 403;
  const day = (iso: string | null | undefined) =>
    iso ? new Date(iso).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" }) : "";

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">
          {t("back")}
        </BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      <div className="mt-6 flex flex-wrap items-center gap-4 text-sm font-semibold text-[var(--text)]">
        <label className="flex items-center gap-2">
          {t("status")}
          <Select value={status} onValueChange={(value) => setStatus(value as ExerciseNameCandidate["status"])} className="min-h-11">
            {STATUSES.map((value) => (
              <option key={value} value={value}>
                {t(`statuses.${value}`)}
              </option>
            ))}
          </Select>
        </label>
        <label className="flex items-center gap-2">
          {t("minOwners")}
          <Select value={String(minOwners)} onValueChange={(value) => setMinOwners(Number(value))} className="min-h-11">
            {MIN_OWNERS.map((value) => (
              <option key={value} value={String(value)}>
                {t("minOwnersValue", { count: value })}
              </option>
            ))}
          </Select>
        </label>
      </div>
      <p className="mt-2 text-xs text-[var(--dim)]">{t("privacyNote")}</p>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {queue.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {queue.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {queue.data?.candidates.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("empty")}</p> : null}

      {queue.data?.candidates.length ? (
        <ul className="mt-6 flex flex-col divide-y divide-[var(--border)] border-y border-[var(--border)]" data-testid="exercise-candidates">
          {queue.data.candidates.map((candidate) => (
            <CandidateRow key={candidate.id} candidate={candidate} catalog={queue.data.catalog} token={token!} seen={day(candidate.last_seen_at)} />
          ))}
        </ul>
      ) : null}
    </main>
  );
}

function CandidateRow({ candidate, catalog, token, seen }: { candidate: ExerciseNameCandidate; catalog: CatalogEntry[]; token: string; seen: string }) {
  const t = useTranslations("PlatformExerciseCandidates");
  const queryClient = useQueryClient();
  const [label, setLabel] = useState(candidate.name);
  const [category, setCategory] = useState<(typeof CATEGORIES)[number]>("strength");
  const [aliasText, setAliasText] = useState("");
  const [aliasOf, setAliasOf] = useState<CatalogEntry | null>(null);
  const decide = useMutation({
    mutationFn: (decision: ExerciseCandidateDecision) => decideExerciseCandidate(token, candidate.id, decision),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["platform", "exercise-candidates"] }),
  });
  const aliasOptions = useMemo<ComboboxOption[]>(
    () =>
      rankItems(aliasText, catalog, (entry) => ({ label: entry.name, alt: entry.catalog_slug }))
        .slice(0, 8)
        .map(({ item }) => ({ id: item.catalog_slug, label: item.name, hint: item.catalog_slug })),
    [aliasText, catalog],
  );
  const pending = candidate.status === "pending";
  const error = decide.error
    ? t(decide.error instanceof ApiError && decide.error.status === 409 ? "conflict" : "decideError")
    : null;

  return (
    <li className="flex flex-col gap-3 py-4" data-testid={`exercise-candidate-${candidate.id}`}>
      <div className="flex flex-wrap items-baseline gap-3">
        <span className="mr-auto text-base font-semibold text-[var(--text)]">{candidate.name}</span>
        <span className="text-sm text-[var(--text-soft)]">
          {t("counts", { owners: candidate.owners_count, uses: candidate.uses_count })}
          {seen ? ` · ${t("lastSeen", { date: seen })}` : ""}
        </span>
        {!pending ? (
          <span className="text-sm font-semibold text-[var(--text)]">
            {t(`statuses.${candidate.status}`)}
            {candidate.catalog_slug ? ` · ${candidate.catalog_slug}` : ""}
          </span>
        ) : null}
      </div>

      {pending ? (
        <div className="grid gap-3 sm:grid-cols-2">
          <fieldset className="flex flex-col gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
            <legend className="px-1 text-xs font-semibold uppercase tracking-[0.18em] text-[var(--muted)]">{t("asEntry")}</legend>
            <input
              aria-label={t("label")}
              value={label}
              maxLength={120}
              onChange={(event) => setLabel(event.target.value)}
              className="min-h-11 rounded-xl px-3 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            <Select value={category} onValueChange={(value) => setCategory(value as (typeof CATEGORIES)[number])} className="min-h-11" aria-label={t("category")}>
              {CATEGORIES.map((value) => (
                <option key={value} value={value}>
                  {t(`categories.${value}`)}
                </option>
              ))}
            </Select>
            <button
              type="button"
              disabled={decide.isPending || !label.trim()}
              onClick={() => decide.mutate({ decision: "entry", label: label.trim(), category })}
              className="min-h-11 rounded-xl bg-[var(--accent)] px-3 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50"
            >
              {t("approveEntry")}
            </button>
          </fieldset>
          <fieldset className="flex flex-col gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
            <legend className="px-1 text-xs font-semibold uppercase tracking-[0.18em] text-[var(--muted)]">{t("asAlias")}</legend>
            <Combobox
              aria-label={t("aliasOf")}
              placeholder={t("aliasOf")}
              value={aliasOf && aliasText === aliasOf.name ? aliasOf.name : aliasText}
              onValueChange={(text) => {
                setAliasText(text);
                setAliasOf(null);
              }}
              options={aliasOptions}
              onPick={(option) => {
                const entry = catalog.find((e) => e.catalog_slug === option.id) ?? null;
                setAliasOf(entry);
                setAliasText(entry?.name ?? "");
              }}
              listLabel={t("aliasOf")}
              className="min-h-11 w-full rounded-xl px-3 text-sm"
              inputStyle={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            <button
              type="button"
              disabled={decide.isPending || !aliasOf}
              onClick={() => aliasOf && decide.mutate({ decision: "alias", catalog_slug: aliasOf.catalog_slug })}
              className="min-h-11 rounded-xl px-3 text-sm font-semibold disabled:opacity-50"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("approveAlias")}
            </button>
            <button
              type="button"
              disabled={decide.isPending}
              onClick={() => decide.mutate({ decision: "reject" })}
              className="min-h-11 rounded-xl px-3 text-sm font-semibold disabled:opacity-50"
              style={{ color: "var(--text-soft)" }}
            >
              {t("reject")}
            </button>
          </fieldset>
        </div>
      ) : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </li>
  );
}
