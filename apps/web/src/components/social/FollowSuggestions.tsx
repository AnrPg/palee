"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  dismissSuggestion,
  fetchFollowSuggestions,
  followSuggested,
  followSuggestionsKey,
  undismissSuggestion,
  type FollowSuggestion,
} from "@/api/follow-suggestions";
import { fetchFollowStatus, followKey, setSocialPrivacy, SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { itemRow, itemRowActions, itemRowMain } from "@/components/ui/rows";
import { useUiTranslations } from "@/i18n/ui";

import { FollowButton } from "./FollowButton";
import { reasonMessage } from "./follow-suggestions-model";
import { PersonAvatar } from "./PersonAvatar";
import { useSocialSummary } from "./use-social";

/**
 * «Ίσως γνωρίζεις» (ADR-561, ANR's picks 2026-11-09): people to follow,
 * one reason each. A row of cards on the Αρχική (hidden when empty, or with
 * «Κρύψε τις προτάσεις», back on from Κοινοποίηση & ορατότητα), the list
 * in «+ Βρες» while its field is empty, and «Και αυτοί ίσως» on a profile
 * right after following it. ✕ removes a person in place with «Αναίρεση».
 */
export function useFollowSuggestions(seed: string | null = null, enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: followSuggestionsKey(seed),
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchFollowSuggestions(token!, seed),
    staleTime: 5 * 60_000,
  });
}

function useReasonLine(person: FollowSuggestion, seedName: string | null) {
  const t = useTranslations("FollowSuggestions");
  const tags = useTranslations("BoxTags");
  const sportLabel = (key: string) => (tags.has(`discipline.${key}`) ? tags(`discipline.${key}`) : null);
  const { key, values } = reasonMessage(person.reason, sportLabel, seedName);
  return t(key, values);
}

/** ✕ and its undo, for one person; the person stays in the list until a refetch. */
function useDismiss(person: FollowSuggestion) {
  const { tokens } = useSession();
  const tUi = useUiTranslations();
  const [dismissed, setDismissed] = useState(false);
  const dismiss = useMutation({
    mutationFn: () => dismissSuggestion(tokens!.access_token, person.id, person.reason.kind),
    onSuccess: () => setDismissed(true),
  });
  const undo = useMutation({
    mutationFn: () => undismissSuggestion(tokens!.access_token, person.id),
    onSuccess: () => setDismissed(false),
  });
  const error = dismiss.error ?? undo.error;
  return {
    dismissed,
    busy: dismiss.isPending || undo.isPending,
    dismiss: () => dismiss.mutate(),
    undo: () => undo.mutate(),
    error: error ? clientErrorMessage(error, tUi) : null,
  };
}

function SuggestedFollow({ person, wide = false }: { person: FollowSuggestion; wide?: boolean }) {
  return (
    <FollowButton
      targetType="user"
      targetId={person.id}
      initialStatus="none"
      followsMe={person.reason.kind === "follows_you"}
      wide={wide}
      onFollow={(token) => followSuggested(token, person.id, person.reason.kind)}
    />
  );
}

function DismissedLine({ onUndo, busy }: { onUndo: () => void; busy: boolean }) {
  const t = useTranslations("FollowSuggestions");
  return (
    <p className="flex flex-wrap items-center gap-x-2 text-sm" style={{ color: "var(--text-soft)" }} data-suggestion-dismissed>
      <span>{t("dismissed")}</span>
      <button type="button" disabled={busy} onClick={onUndo} className="min-h-11 font-bold disabled:opacity-50" style={{ color: "var(--primary)" }}>
        {t("undo")}
      </button>
    </p>
  );
}

function DismissButton({ name, onClick, busy }: { name: string; onClick: () => void; busy: boolean }) {
  const t = useTranslations("FollowSuggestions");
  return (
    <button
      type="button"
      aria-label={t("dismiss", { name })}
      disabled={busy}
      onClick={onClick}
      className="hit-area flex h-8 w-8 shrink-0 items-center justify-center rounded-full disabled:opacity-50"
      style={{ color: "var(--dim)" }}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden="true">
        <path d="M18 6 6 18M6 6l12 12" />
      </svg>
    </button>
  );
}

/** A card of the horizontal row (Αρχική, «Και αυτοί ίσως»). */
function SuggestionCard({ person, seedName }: { person: FollowSuggestion; seedName: string | null }) {
  const name = person.nickname ?? person.handle ?? "?";
  const reason = useReasonLine(person, seedName);
  const state = useDismiss(person);
  return (
    <li
      className="relative flex w-40 shrink-0 snap-start flex-col items-center gap-1 rounded-2xl p-3 text-center"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-suggestion={person.id}
    >
      {state.dismissed ? (
        <div className="flex flex-1 items-center">
          <DismissedLine onUndo={state.undo} busy={state.busy} />
        </div>
      ) : (
        <>
          <span className="absolute end-1 top-1">
            <DismissButton name={name} onClick={state.dismiss} busy={state.busy} />
          </span>
          <Link href={`/people/${person.id}`} className="flex min-w-0 flex-col items-center gap-1">
            <PersonAvatar name={name} url={person.avatar_url} size={52} />
            <span className="w-full truncate font-bold" style={{ color: "var(--text)" }}>{name}</span>
            {person.handle ? <span className="w-full truncate text-xs" style={{ color: "var(--dim)" }}>@{person.handle}</span> : null}
          </Link>
          <span className="line-clamp-2 min-h-8 text-xs" style={{ color: "var(--text-soft)" }}>{reason}</span>
          <div className="mt-auto w-full">
            <SuggestedFollow person={person} wide />
          </div>
        </>
      )}
      {state.error ? <ErrorNotice>{state.error}</ErrorNotice> : null}
    </li>
  );
}

/** A row of the full list («+ Βρες»). */
export function SuggestionRow({ person }: { person: FollowSuggestion }) {
  const name = person.nickname ?? person.handle ?? "?";
  const reason = useReasonLine(person, null);
  const state = useDismiss(person);
  return (
    <li className={`${itemRow} rounded-3xl p-3`} style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-suggestion={person.id}>
      {state.dismissed ? (
        <DismissedLine onUndo={state.undo} busy={state.busy} />
      ) : (
        <>
          <Link href={`/people/${person.id}`} className={itemRowMain}>
            <PersonAvatar name={name} url={person.avatar_url} />
            <span className="min-w-0">
              <span className="block truncate font-bold" style={{ color: "var(--text)" }}>
                {name}
                {person.handle ? <span className="ms-1.5 text-xs font-normal" style={{ color: "var(--dim)" }}>@{person.handle}</span> : null}
              </span>
              <span className="block text-xs" style={{ color: "var(--text-soft)" }}>{reason}</span>
            </span>
          </Link>
          <div className={itemRowActions}>
            <SuggestedFollow person={person} />
            <DismissButton name={name} onClick={state.dismiss} busy={state.busy} />
          </div>
        </>
      )}
      {state.error ? <ErrorNotice>{state.error}</ErrorNotice> : null}
    </li>
  );
}

function CardRow({ people, seedName }: { people: FollowSuggestion[]; seedName: string | null }) {
  return (
    <ul className="-mx-1 flex snap-x snap-mandatory gap-2.5 overflow-x-auto px-1 pb-1" data-suggestion-row>
      {people.map((person) => (
        <SuggestionCard key={person.id} person={person} seedName={seedName} />
      ))}
    </ul>
  );
}

/** Αρχική: the row, hidden when empty or when the person hid it. */
export function HomeFollowSuggestions() {
  const t = useTranslations("FollowSuggestions");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const summary = useSocialSummary();
  const shown = summary.data?.privacy?.show_follow_suggestions ?? false;
  const suggestions = useFollowSuggestions(null, shown);
  const hide = useMutation({
    mutationFn: () => setSocialPrivacy(tokens!.access_token, { show_follow_suggestions: false }),
    onSuccess: (privacy) =>
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) => (current ? { ...current, privacy } : current)),
  });
  const people = suggestions.data?.people ?? [];
  if (!shown || people.length === 0) return null;
  return (
    <HubCard>
      <section aria-labelledby="follow-suggestions-title" data-follow-suggestions="home">
        <div className="mb-3 flex items-center justify-between gap-2">
          <h2 id="follow-suggestions-title" className="font-bold" style={{ color: "var(--text)" }}>{t("title")}</h2>
          <div className="flex shrink-0 items-center gap-1">
            <Link href="/clubs/find" className="min-h-11 content-center px-1 text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {t("seeAll")}
            </Link>
            <MoreMenu label={t("more")} items={[{ label: t("hide"), onSelect: () => hide.mutate() }]} />
          </div>
        </div>
        <CardRow people={people} seedName={null} />
        {hide.error ? <ErrorNotice>{clientErrorMessage(hide.error, tUi)}</ErrorNotice> : null}
      </section>
    </HubCard>
  );
}

/** «+ Βρες» while its field is empty: the whole list. */
export function FindFollowSuggestions() {
  const t = useTranslations("FollowSuggestions");
  const suggestions = useFollowSuggestions();
  const people = suggestions.data?.people ?? [];
  if (suggestions.isError) return <ErrorNotice>{t("failed")}</ErrorNotice>;
  if (people.length === 0) return null;
  return (
    <section aria-labelledby="find-suggestions-title" className="space-y-2" data-follow-suggestions="find">
      <h2 id="find-suggestions-title" className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {t("forYou")}
      </h2>
      <ul className="flex flex-col gap-2">
        {people.map((person) => (
          <SuggestionRow key={person.id} person={person} />
        ))}
      </ul>
    </section>
  );
}

/**
 * A profile: «Και αυτοί ίσως», shown once the viewer follows (or asked to
 * follow) this person during the visit, seeded with the people they follow.
 */
export function AfterFollowSuggestions({ personId, personName }: { personId: string; personName: string | null }) {
  const t = useTranslations("FollowSuggestions");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  // The same query as the profile's FollowButton, so both read one cached status.
  const status = useQuery({
    queryKey: followKey("user", personId),
    enabled: Boolean(token),
    queryFn: () => fetchFollowStatus(token!, "user", personId),
  });
  // What the button said when the profile first showed it.
  const [startedAs, setStartedAs] = useState<string | null>(status.data ?? null);
  if (startedAs === null && status.data) setStartedAs(status.data);
  const followedNow = startedAs === "none" && (status.data === "active" || status.data === "requested");
  const suggestions = useFollowSuggestions(personId, followedNow);
  const people = suggestions.data?.people ?? [];
  if (!followedNow || people.length === 0) return null;
  return (
    <section aria-labelledby="also-suggestions-title" className="mt-4 space-y-2" data-follow-suggestions="profile">
      <h2 id="also-suggestions-title" className="font-bold" style={{ color: "var(--text)" }}>{t("also")}</h2>
      <CardRow people={people} seedName={personName} />
    </section>
  );
}
