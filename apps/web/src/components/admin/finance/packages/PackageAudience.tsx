"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import { listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { searchPeople, type PeopleSearchPerson } from "@/api/conversations";
import type { FinanceRecord } from "@/api/finance";
import {
  PACKAGE_AUDIENCE_KEY,
  deleteAudienceException,
  fetchPackageAudience,
  putAudienceException,
  setBoxAudience,
  setPackageAudience,
  type AudienceEffect,
  type BoxAudience,
  type PackageAudience,
  type PackageAudienceSettings,
} from "@/api/package-audience";
import { HoverHint } from "@/components/HelpTooltip";
import { useSession } from "@/components/session-provider";
import { Combobox } from "@/components/ui/Combobox";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { BOX_AUDIENCES, PACKAGE_AUDIENCES, exceptionsFor, packageAudience, personName, personOptions, type PersonOption } from "./package-audience";

/**
 * ADR-553 (mockup Q1 option A, ANR 2026-11-08): «Ποιος βλέπει τα πακέτα
 * συνδρομής» is one row above the package list, one choice for the box's
 * Palee page and its website alike; each package has «Ποιος το βλέπει» in
 * its advanced settings («Όπως το box» until changed). People the box always
 * or never shows its packages to stay folded away until asked for.
 */

function useAudienceSettings(token: string) {
  return useQuery({ queryKey: PACKAGE_AUDIENCE_KEY, queryFn: () => fetchPackageAudience(token), enabled: Boolean(token) });
}

/** The row above the package list, and its sheet. */
export function BoxAudienceRow({ token }: { token: string }) {
  const t = useTranslations("PackageAudience");
  const settings = useAudienceSettings(token);
  const [open, setOpen] = useState(false);
  const audience = settings.data?.audience ?? "all";
  const people = exceptionsFor(settings.data, null).length;

  return (
    <>
      {/* ANR 2026-11-08: a box-wide setting, not a package, so it is one
          dark row and never looks like the package cards below it. */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-11 w-full items-center gap-3 rounded-xl px-4 py-2.5 text-start"
        style={{ background: "var(--text)", color: "var(--bg)" }}
        data-testid="package-audience-row"
      >
        <AudienceIcon audience={audience} inverse />
        <span className="min-w-0 flex-1 truncate text-sm font-semibold">{t("title")}</span>
        <span className="shrink-0 text-sm" style={{ opacity: 0.75 }} data-testid="package-audience-summary">
          {settings.isLoading ? "…" : t(`summary_${audience}`)}
          {people > 0 ? ` · ${t("peopleCount", { count: people })}` : ""}
        </span>
        <span aria-hidden="true" style={{ opacity: 0.75 }}>›</span>
      </button>
      {open ? (
        <Dialog onClose={() => setOpen(false)} title={t("title")} size="sm" variant="sheet" testId="package-audience-sheet">
          <BoxAudienceChoice token={token} settings={settings.data} />
        </Dialog>
      ) : null}
    </>
  );
}

function BoxAudienceChoice({ token, settings }: { token: string; settings: PackageAudienceSettings | undefined }) {
  const t = useTranslations("PackageAudience");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: (audience: BoxAudience) => setBoxAudience(token, audience),
    onSuccess: async (data) => {
      queryClient.setQueryData(PACKAGE_AUDIENCE_KEY, data);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
    },
  });
  const value = mutation.isPending && mutation.variables ? mutation.variables : (settings?.audience ?? "all");

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("intro")}</p>
      <ChoiceList
        label={t("title")}
        value={value}
        disabled={!settings || mutation.isPending}
        onChange={(next) => mutation.mutate(next)}
        options={BOX_AUDIENCES.map((audience) => ({ value: audience, label: t(`box_${audience}`), hint: t(`boxHint_${audience}`) }))}
        testId="package-audience-box"
      />
      {mutation.error ? <ErrorNotice>{localizeError(mutation.error, ui)}</ErrorNotice> : null}
      <PeopleExceptions token={token} settings={settings} packageId={null} />
    </div>
  );
}

/** «Ποιος το βλέπει» in a package's advanced settings. */
export function PackageAudienceCard({ token, pkg }: { token: string; pkg: FinanceRecord }) {
  const t = useTranslations("PackageAudience");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const settings = useAudienceSettings(token);
  const packageId = String(pkg.id ?? "");
  const mutation = useMutation({
    mutationFn: (audience: PackageAudience) => setPackageAudience(token, packageId, audience),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] }),
      ]);
    },
  });
  const stored = packageAudience(pkg);
  const value = mutation.isPending ? (mutation.variables ?? null) : mutation.isSuccess ? (mutation.data?.audience ?? null) : stored;
  const boxAudience = settings.data?.audience ?? "all";

  return (
    <section className="space-y-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="package-audience-card">
      <h4 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("packageTitle")}</h4>
      <ChoiceList
        label={t("packageTitle")}
        value={value ?? "inherit"}
        disabled={mutation.isPending}
        onChange={(next) => mutation.mutate(next === "inherit" ? null : next)}
        options={PACKAGE_AUDIENCES.map((audience) =>
          audience === null
            ? { value: "inherit" as const, label: t("package_inherit"), hint: t("inheritNow", { current: t(`box_${boxAudience}`) }) }
            : { value: audience, label: t(`package_${audience}`) },
        )}
        testId="package-audience-package"
      />
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("bothPlaces")}</p>
      {mutation.error ? <ErrorNotice>{localizeError(mutation.error, ui)}</ErrorNotice> : null}
      <PeopleExceptions token={token} settings={settings.data} packageId={packageId} />
    </section>
  );
}

type Choice<T extends string> = { value: T; label: string; hint?: string };

function ChoiceList<T extends string>({
  label,
  value,
  options,
  onChange,
  disabled,
  testId,
}: {
  label: string;
  value: T;
  options: Choice<T>[];
  onChange: (value: T) => void;
  disabled?: boolean;
  testId: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-col gap-2" data-testid={testId}>
      {options.map((option) => {
        const checked = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={checked}
            disabled={disabled}
            onClick={() => (checked ? undefined : onChange(option.value))}
            className="flex min-h-11 w-full items-center justify-between gap-3 rounded-2xl px-4 py-2 text-start disabled:opacity-70"
            style={{
              background: "var(--panel-muted)",
              border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`,
              boxShadow: checked ? "0 0 0 1px var(--primary)" : undefined,
            }}
            data-testid={`${testId}-${option.value}`}
          >
            <span className="min-w-0">
              <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{option.label}</span>
              {option.hint ? <span className="block text-xs" style={{ color: "var(--dim)" }}>{option.hint}</span> : null}
            </span>
            {checked ? <span aria-hidden="true" style={{ color: "var(--primary)" }}>✓</span> : null}
          </button>
        );
      })}
    </div>
  );
}

/** «Εξαιρέσεις για συγκεκριμένα άτομα»: folded until asked for. */
function PeopleExceptions({ token, settings, packageId }: { token: string; settings: PackageAudienceSettings | undefined; packageId: string | null }) {
  const t = useTranslations("PackageAudience");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const rows = exceptionsFor(settings, packageId);
  const [open, setOpen] = useState(false);
  const [adding, setAdding] = useState<AudienceEffect | null>(null);
  const scope = packageId === null ? "box" : "package";

  const save = (data: PackageAudienceSettings) => queryClient.setQueryData(PACKAGE_AUDIENCE_KEY, data);
  const add = useMutation({
    mutationFn: (input: { person: PersonOption; effect: AudienceEffect }) =>
      putAudienceException(token, { user_id: input.person.id, effect: input.effect, package_id: packageId }),
    onSuccess: (data) => {
      save(data);
      setAdding(null);
    },
  });
  const remove = useMutation({ mutationFn: (id: string) => deleteAudienceException(token, id), onSuccess: save });

  if (!open && rows.length === 0) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }} data-testid={`package-audience-people-${scope}`}>
        {t("peopleToggle")} ›
      </button>
    );
  }

  return (
    <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }} data-testid={`package-audience-people-list-${scope}`}>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("peopleTitle")}</p>
      {(["show", "hide"] as const).map((effect) => (
        <div key={effect} className="flex flex-col gap-2">
          <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t(`${scope}_${effect}`)}</p>
          <ul className="flex flex-col gap-1">
            {rows
              .filter((row) => row.effect === effect)
              .map((row) => {
                const name = personName(row.person) ?? t("unknownPerson");
                return (
                  <li key={row.id} className="flex min-h-11 items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
                    <span className="min-w-0 flex-1 truncate">
                      {name}
                      {row.person.handle && row.person.nickname ? <span style={{ color: "var(--dim)" }}> @{row.person.handle}</span> : null}
                    </span>
                    <button
                      type="button"
                      onClick={() => remove.mutate(row.id)}
                      disabled={remove.isPending}
                      aria-label={t("remove", { name })}
                      className="flex h-11 w-11 items-center justify-center rounded-xl"
                      style={{ color: "var(--dim)" }}
                    >
                      ✕
                    </button>
                  </li>
                );
              })}
          </ul>
          {adding === effect ? (
            <PersonSearch
              token={token}
              taken={rows.map((row) => row.person.id)}
              onPick={(person) => add.mutate({ person, effect })}
              onCancel={() => setAdding(null)}
            />
          ) : (
            <button type="button" onClick={() => setAdding(effect)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }} data-testid={`package-audience-add-${scope}-${effect}`}>
              + {t("addPerson")}
            </button>
          )}
        </div>
      ))}
      {add.error || remove.error ? <ErrorNotice>{localizeError((add.error ?? remove.error) as Error, ui)}</ErrorNotice> : null}
    </div>
  );
}

/** The box's people first, then anyone on Palee, by name or @handle. */
function PersonSearch({ token, taken, onPick, onCancel }: { token: string; taken: string[]; onPick: (person: PersonOption) => void; onCancel: () => void }) {
  const t = useTranslations("PackageAudience");
  const [text, setText] = useState("");
  const [found, setFound] = useState<{ members: AthleteOption[]; people: PeopleSearchPerson[] }>({ members: [], people: [] });
  const query = text.trim().replace(/^@/, "");

  useEffect(() => {
    if (query.length === 0) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      Promise.all([
        listAthletes(token, query, { includeMembers: true }).catch(() => [] as AthleteOption[]),
        searchPeople(token, query, controller.signal).catch(() => [] as PeopleSearchPerson[]),
      ]).then(([members, people]) => {
        if (!controller.signal.aborted) setFound({ members: Array.isArray(members) ? members : [], people });
      });
    }, 250);
    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [query, token]);

  const options = query.length === 0 ? [] : personOptions(found.members, found.people, taken);

  return (
    <div className="flex items-center gap-2">
      <div className="min-w-0 flex-1">
        <Combobox
          value={text}
          onValueChange={setText}
          options={options.map((option) => ({
            id: option.id,
            label: option.label,
            hint: option.member ? t("boxMember") : option.handle ? `@${option.handle}` : undefined,
          }))}
          onPick={(picked) => {
            const person = options.find((option) => option.id === picked.id);
            if (person) onPick(person);
          }}
          emptyText={query.length > 0 ? t("noMatches") : undefined}
          listLabel={t("addPerson")}
          placeholder={t("searchPlaceholder")}
          aria-label={t("addPerson")}
          className="min-h-11 w-full rounded-xl px-3 text-sm"
          inputStyle={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="package-audience-search"
        />
      </div>
      <button type="button" onClick={onCancel} className="min-h-11 px-2 text-sm font-semibold" style={{ color: "var(--dim)" }}>
        {t("cancel")}
      </button>
    </div>
  );
}

const AUDIENCE_COLOR: Record<BoxAudience, string> = { all: "var(--success)", own: "var(--warning)", none: "var(--danger)" };

/** A line eye, coloured by who sees: everyone, only who holds it, no one. */
function AudienceIcon({ audience, inverse = false }: { audience: BoxAudience; inverse?: boolean }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke={inverse ? "currentColor" : AUDIENCE_COLOR[audience]}
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="shrink-0"
    >
      <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" />
      {audience === "own" ? <path d="M9 13.5a3 3 0 0 1 6 0" /> : <circle cx="12" cy="12" r="3" />}
      {audience === "own" ? <circle cx="12" cy="9.8" r="1.4" /> : null}
      {audience === "none" ? <path d="M4 4l16 16" /> : null}
    </svg>
  );
}

/**
 * «Ποιος το βλέπει» on every package row (ANR 2026-11-08: a colour-coded
 * line icon, not a chip; hovering names it). Every package has one, whether
 * it follows the box or chose for itself.
 */
export function PackageAudienceBadge({ pkg }: { pkg: FinanceRecord }) {
  const t = useTranslations("PackageAudience");
  const { tokens } = useSession();
  const settings = useAudienceSettings(tokens?.access_token ?? "");
  const own = packageAudience(pkg);
  const audience = own ?? settings.data?.audience ?? "all";
  const people = exceptionsFor(settings.data, typeof pkg.id === "string" ? pkg.id : null).length;
  const label = [t(`badge_${audience}`), own === null ? t("package_inherit") : null, people > 0 ? t("peopleCount", { count: people }) : null]
    .filter(Boolean)
    .join(" · ");
  return (
    <HoverHint hint={label}>
      <span role="img" aria-label={label} className="inline-flex" data-testid="package-audience-badge" data-audience={audience}>
        <AudienceIcon audience={audience} />
      </span>
    </HoverHint>
  );
}
