"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import { ApiError, apiRequest } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import type { WorkoutKindAddition } from "@/lib/workout-kinds";
import { WORKOUT_TYPE_FAMILIES, type WorkoutTypeFamily } from "@/lib/workout-types";

/** The 12 locales a Palee kind is named in (ADR-690). */
export const KIND_LOCALES = ["en", "el", "de", "es", "fr", "it", "nl", "pt_PT", "ru", "bg", "ar", "he"] as const;

export type WorkoutKindCandidate = {
  id: string;
  label: string;
  status: "pending" | "adopted" | "aliased" | "kept";
  boxes: number;
  family_votes: Record<string, number>;
  profile_suggestions: number;
  decision: Record<string, unknown> | null;
  first_seen_at: string;
  decided_at: string | null;
};

type Queue = { pending: WorkoutKindCandidate[]; decided: WorkoutKindCandidate[]; additions: WorkoutKindAddition[] };

type Decision =
  | { decision: "adopt"; key: string; family: WorkoutTypeFamily; labels: Record<string, string> }
  | { decision: "alias"; target: string }
  | { decision: "keep" };

const QUEUE_KEY = ["platform", "workout-kinds"] as const;

/** A latin key from a name: «Animal Flow» → animal_flow (the team edits it). */
export function kindKeyFrom(label: string) {
  const key = label
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);
  return /^[a-z]/.test(key) ? key : "";
}

/** The family most boxes chose for a name. */
export function likeliestFamily(votes: Record<string, number>): WorkoutTypeFamily | null {
  const best = Object.entries(votes).sort((a, b) => b[1] - a[1])[0]?.[0];
  return WORKOUT_TYPE_FAMILIES.some((group) => group.family === best) ? (best as WorkoutTypeFamily) : null;
}

/**
 * ADR-690: the Palee team's queue of workout type names. Box types and the
 * public page's «Πρότεινέ το» disciplines are one row per name. A name
 * becomes a kind for everyone (with a name in every language), is the same
 * as an existing kind, or stays a box type. The boxes' WODs follow, and
 * their owners hear about it.
 */
export function PlatformWorkoutKinds() {
  const t = useTranslations("PlatformWorkoutKinds");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queue = useQuery({
    queryKey: QUEUE_KEY,
    queryFn: () => apiRequest<Queue>("/platform/workout-kinds", { token: token! }),
    enabled: Boolean(token),
  });
  const forbidden = queue.error instanceof ApiError && queue.error.status === 403;

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {queue.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {queue.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {queue.data && queue.data.pending.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("empty")}</p> : null}

      {queue.data && queue.data.pending.length > 0 ? (
        <ul className="mt-6 flex flex-col gap-3" aria-label={t("pending")}>
          {queue.data.pending.map((candidate) => (
            <CandidateRow key={candidate.id} candidate={candidate} additions={queue.data!.additions} token={token!} />
          ))}
        </ul>
      ) : null}

      {queue.data && queue.data.decided.length > 0 ? (
        <section className="mt-10 space-y-2" aria-label={t("decided")}>
          <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("decided")}</h2>
          <ul className="flex flex-col divide-y divide-[var(--border)] border-y border-[var(--border)]">
            {queue.data.decided.map((candidate) => (
              <li key={candidate.id} className="flex flex-wrap items-center gap-2 py-2 text-sm">
                <span className="mr-auto font-semibold text-[var(--text)]">{candidate.label}</span>
                <span className="text-[var(--text-soft)]">
                  {t(`status_${candidate.status}`, { target: String(candidate.decision?.target ?? "") })}
                  {candidate.decided_at ? ` · ${new Date(candidate.decided_at).toLocaleDateString(locale, { day: "numeric", month: "short" })}` : ""}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}

function CandidateRow({ candidate, additions, token }: { candidate: WorkoutKindCandidate; additions: WorkoutKindAddition[]; token: string }) {
  const t = useTranslations("PlatformWorkoutKinds");
  const i18n = useUiTranslations();
  const labels = useWorkoutTypeLabels();
  const queryClient = useQueryClient();
  const [mode, setMode] = useState<"adopt" | "alias" | null>(null);
  const [key, setKey] = useState(() => kindKeyFrom(candidate.label));
  const [family, setFamily] = useState<WorkoutTypeFamily | null>(() => likeliestFamily(candidate.family_votes));
  const [names, setNames] = useState<Record<string, string>>(() => Object.fromEntries(KIND_LOCALES.map((code) => [code, candidate.label])));
  const [target, setTarget] = useState("");
  const decide = useMutation({
    mutationFn: (body: Decision) =>
      apiRequest<WorkoutKindCandidate>(`/platform/workout-kinds/${candidate.id}/decision`, { token, method: "POST", body }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: QUEUE_KEY }),
  });
  const votes = Object.entries(candidate.family_votes)
    .sort((a, b) => b[1] - a[1])
    .map(([name, count]) => t("votes", { family: labels.family(name), count }))
    .join(" · ");
  const button = "rounded-full border border-[var(--border)] px-4 py-2 text-sm font-semibold text-[var(--text-soft)] disabled:opacity-40";
  const primary = "rounded-full bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-40";
  const field = "min-h-10 w-full rounded-xl border border-[var(--border)] bg-[var(--bg)] px-3 text-sm text-[var(--text)]";
  const namesComplete = KIND_LOCALES.every((code) => names[code]?.trim().length >= 2);

  return (
    <li className="space-y-3 rounded-2xl border border-[var(--border)] bg-[var(--card)] p-4" data-testid="workout-kind-candidate">
      <div className="flex flex-wrap items-start gap-3">
        <div className="mr-auto">
          <p className="font-semibold text-[var(--text)]">{candidate.label}</p>
          <p className="text-sm text-[var(--text-soft)]">
            {t("boxes", { count: candidate.boxes })}
            {candidate.profile_suggestions > 0 ? ` · ${t("suggestions", { count: candidate.profile_suggestions })}` : ""}
          </p>
          {votes ? <p className="text-xs text-[var(--dim)]">{votes}</p> : null}
        </div>
        <button type="button" className={button} disabled={decide.isPending} onClick={() => decide.mutate({ decision: "keep" })}>
          {t("keep")}
        </button>
        <button type="button" className={button} aria-expanded={mode === "alias"} onClick={() => setMode(mode === "alias" ? null : "alias")}>
          {t("alias")}
        </button>
        <button type="button" className={primary} aria-expanded={mode === "adopt"} onClick={() => setMode(mode === "adopt" ? null : "adopt")}>
          {t("adopt")}
        </button>
      </div>

      {mode === "alias" ? (
        <div className="flex flex-wrap items-center gap-2">
          <Select value={target} onValueChange={setTarget} placeholder={t("aliasTarget")} aria-label={t("aliasTarget")} className={`${field} sm:w-auto sm:min-w-64`}>
            {WORKOUT_TYPE_FAMILIES.map((group) => (
              <optgroup key={group.family} label={labels.family(group.family)}>
                {[...group.types, ...additions.filter((addition) => addition.family === group.family).map((addition) => addition.key)].map((ref) => (
                  <option key={ref} value={ref}>
                    {labels.type(ref)}
                  </option>
                ))}
              </optgroup>
            ))}
          </Select>
          <button type="button" className={primary} disabled={!target || decide.isPending} onClick={() => decide.mutate({ decision: "alias", target })}>
            {t("aliasConfirm")}
          </button>
        </div>
      ) : null}

      {mode === "adopt" ? (
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (family && key && namesComplete) decide.mutate({ decision: "adopt", key, family, labels: names });
          }}
        >
          <label className="block space-y-1 text-sm">
            <span className="font-semibold text-[var(--text)]">{t("key")}</span>
            <input value={key} onChange={(event) => setKey(event.target.value)} pattern="[a-z][a-z0-9_]{1,47}" className={field} />
            <span className="text-xs text-[var(--dim)]">{t("keyHint")}</span>
          </label>
          <div className="space-y-1 text-sm">
            <span className="font-semibold text-[var(--text)]">{t("family")}</span>
            <div className="flex flex-wrap gap-2" role="radiogroup" aria-label={t("family")}>
              {WORKOUT_TYPE_FAMILIES.map((group) => (
                <button
                  key={group.family}
                  type="button"
                  role="radio"
                  aria-checked={family === group.family}
                  onClick={() => setFamily(group.family)}
                  className={`min-h-9 rounded-full border px-3 text-sm font-semibold ${family === group.family ? "border-[var(--primary)] text-[var(--text)]" : "border-[var(--border)] text-[var(--muted)]"}`}
                >
                  {labels.family(group.family)}
                </button>
              ))}
            </div>
          </div>
          <fieldset className="grid gap-2 sm:grid-cols-2">
            <legend className="mb-1 text-sm font-semibold text-[var(--text)]">{t("names")}</legend>
            {KIND_LOCALES.map((code) => (
              <label key={code} className="flex items-center gap-2 text-sm">
                <span className="w-12 shrink-0 font-mono text-xs text-[var(--dim)]">{code}</span>
                <input
                  value={names[code] ?? ""}
                  maxLength={40}
                  onChange={(event) => setNames((current) => ({ ...current, [code]: event.target.value }))}
                  className={field}
                  dir={code === "ar" || code === "he" ? "rtl" : undefined}
                />
              </label>
            ))}
          </fieldset>
          <button type="submit" className={primary} disabled={!family || !key || !namesComplete || decide.isPending}>
            {t("adoptConfirm")}
          </button>
        </form>
      ) : null}

      {decide.error ? <ErrorNotice>{localizeError(decide.error, i18n)}</ErrorNotice> : null}
    </li>
  );
}
