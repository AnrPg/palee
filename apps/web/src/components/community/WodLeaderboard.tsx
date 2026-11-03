"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";

import {
  fetchWorkoutLeaderboard,
  leaderboardKey,
  putPaleeConsent,
  type LeaderboardWindow,
  type PaleeChoice,
  type WorkoutLeaderboard as Board,
  type WorkoutLeaderboardRow,
} from "@/api/training-floor";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { clubInitials } from "@/components/community/community";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { Dialog } from "@/components/ui/Dialog";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import {
  DEFAULT_LEADERBOARD_FILTERS,
  LEADERBOARD_WINDOWS,
  advancedActive,
  ageGroupLabel,
  defaultWindow,
  leaderboardChips,
  leaderboardQuery,
  toggleChip,
  type LeaderboardChip,
  type LeaderboardFilters,
} from "@/lib/training-floor";

/**
 * The #wod leaderboard with filters (ADR-356, ANR mockup d2 A): one row of
 * chips (Όλοι · my division · my age group · my level), the percentile on my
 * own row, and time window, branch and buddies under «Προχωρημένα».
 *
 * Only people who opted in see this; until the filtered board answers, or
 * for anyone who did not opt in, the card's own list (`fallback`) stays.
 *
 * ADR-394 (ANR option A): when the coach tagged the WOD as a benchmark, the
 * chips start with «Το box μου» and «Όλο το Palee». The first tap on «Όλο το
 * Palee» asks once whether the person's score goes on that board; the answer
 * is kept on the server and changed in «Κοινοποίηση και ορατότητα». Palee
 * rows show the person's box under their name.
 */
export function WodLeaderboard({
  slug,
  workoutId,
  date,
  fallback,
}: {
  slug: string;
  workoutId: string;
  /** The gym's own date of the WOD (YYYY-MM-DD). */
  date: string;
  fallback: ReactNode;
}) {
  const t = useTranslations("TrainingFloor");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { memberships } = useSelectedMembershipRole();
  const homeLocationId =
    (memberships.find((entry) => entry.organization.slug === slug) as { home_location_id?: string | null } | undefined)
      ?.home_location_id ?? null;
  const [filters, setFilters] = useState<LeaderboardFilters>(DEFAULT_LEADERBOARD_FILTERS);
  const [asking, setAsking] = useState(false);
  const queryClient = useQueryClient();
  const query = leaderboardQuery(filters, { date, homeLocationId });
  const board = useQuery({
    queryKey: leaderboardKey(slug, workoutId, query),
    enabled: Boolean(token),
    queryFn: () => fetchWorkoutLeaderboard(token!, slug, workoutId, query),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
  });
  const answer = useMutation({
    mutationFn: (choice: PaleeChoice) => putPaleeConsent(token!, choice),
    onSuccess: () => {
      setAsking(false);
      setFilters((current) => toggleChip(current, { kind: "scope", value: "palee", on: false }));
      void queryClient.invalidateQueries({ queryKey: ["training-floor"] });
    },
  });

  // The answer was withdrawn elsewhere: back to the box's own board.
  const paleeFailed = board.isError && filters.scope === "palee";
  useEffect(() => {
    if (paleeFailed) setFilters((current) => toggleChip(current, { kind: "scope", value: "box", on: false }));
  }, [paleeFailed]);

  const data = board.data;
  if (!data || !data.opted_in) return <>{fallback}</>;

  const palee = filters.scope === "palee";

  const year = Number(date.slice(0, 4));
  const ownScale = data.me?.scale_level_slug
    ? { slug: data.me.scale_level_slug, label: scaleLabel(data, data.me.scale_level_slug) }
    : null;
  const chips = leaderboardChips(filters, {
    division: (data.profile?.division as "women" | "men" | null | undefined) ?? null,
    birthYear: data.profile?.birth_year ?? null,
    year,
    scale: ownScale,
  }, { benchmark: Boolean(data.benchmark) });
  const profileMissing = !data.profile?.division || !data.profile?.birth_year;
  const branchOffered = !palee && Boolean(homeLocationId) && data.options.scopes.includes("branch");
  const meListed = data.rows.some((row) => row.me);

  function tap(chip: LeaderboardChip) {
    if (chip.kind === "scope" && chip.value === "palee" && !chip.on && !data?.palee_consent) {
      setAsking(true);
      return;
    }
    setFilters(toggleChip(filters, chip));
  }

  return (
    <div className="flex flex-col gap-3" data-testid="wod-leaderboard">
      <div role="group" aria-label={t("lbChipsAria")} className="flex flex-wrap gap-1.5">
        {chips.map((chip) => (
          <button
            key={chip.kind === "scope" ? `scope-${chip.value}` : chip.kind}
            type="button"
            aria-pressed={chip.on}
            onClick={() => tap(chip)}
            className="min-h-9 rounded-full px-3 text-sm font-semibold"
            style={
              chip.on
                ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
                : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }
            }
          >
            {chipLabel(chip, t)}
          </button>
        ))}
      </div>

      {data.rows.length === 0 && data.me ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("lbEmpty")}</p>
      ) : (
        <ol className="flex flex-col gap-1" aria-label={t("lbListAria", { count: data.total })} aria-busy={board.isFetching}>
          {data.rows.map((row, index) => (
            <Row
              key={row.user_id ?? `${row.rank}-${index}`}
              row={row}
              scale={row.scale_level_slug ? scaleLabel(data, row.scale_level_slug) : null}
              paleeTotal={palee ? data.total : null}
            />
          ))}
          {data.me && !meListed ? (
            <>
              <li aria-hidden="true" className="px-2 text-sm" style={{ color: "var(--dim)" }}>…</li>
              <Row
                row={data.me}
                scale={data.me.scale_level_slug ? scaleLabel(data, data.me.scale_level_slug) : null}
                paleeTotal={palee ? data.total : null}
              />
            </>
          ) : null}
          {!data.me ? (
            <li className="flex items-center gap-3 rounded-xl px-2 py-1.5" style={{ background: "var(--panel-raised)" }}>
              <span className="w-5 text-center font-mono text-sm" style={{ color: "var(--dim)" }}>–</span>
              <b className="grow text-sm" style={{ color: "var(--text)" }}>{t("lbYou")}</b>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("lbNoScore")}</span>
            </li>
          ) : null}
        </ol>
      )}

      {profileMissing ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("lbProfileHint")}{" "}
          <Link href="/me/sharing#leaderboard" className="font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("lbProfileLink")}
          </Link>
        </p>
      ) : null}

      <AdvancedDisclosure count={palee ? 1 : branchOffered ? 3 : 2} testId="wod-leaderboard-advanced">
        <SegmentPicker<LeaderboardWindow>
          ariaLabel={t("lbWindow")}
          semantics="radiogroup"
          value={filters.window}
          onChange={(window) => setFilters({ ...filters, window })}
          options={LEADERBOARD_WINDOWS.filter((window) => data.options.windows.includes(window)).map((window) => ({
            value: window,
            label: t(`lbWindow_${window}`),
          }))}
        />
        {branchOffered ? (
          <SegmentPicker<"box" | "branch">
            ariaLabel={t("lbScope")}
            semantics="radiogroup"
            value={filters.scope}
            onChange={(scope) => setFilters({ ...filters, scope })}
            options={[
              { value: "box", label: t("lbScope_box") },
              { value: "branch", label: t("lbScope_branch") },
            ]}
          />
        ) : null}
        {palee ? null : (
          <Switch
            label={t("lbBuddies")}
            hint={t("lbBuddiesHint")}
            checked={filters.buddies}
            onChange={(buddies) => setFilters({ ...filters, buddies })}
          />
        )}
        {advancedActive(filters) ? (
          <button
            type="button"
            onClick={() =>
              setFilters(
                palee
                  ? { ...filters, window: defaultWindow("palee") }
                  : { ...filters, window: defaultWindow("box"), scope: "box", buddies: false },
              )
            }
            className="text-sm font-semibold underline"
            style={{ color: "var(--primary)" }}
          >
            {palee ? t("lbAdvancedResetPalee") : t("lbAdvancedReset")}
          </button>
        ) : null}
      </AdvancedDisclosure>

      {asking ? (
        <Dialog
          onClose={() => setAsking(false)}
          dismissible={!answer.isPending}
          size="sm"
          variant="sheet"
          eyebrow={t("lbChipPalee")}
          title={t("lbPaleeAskTitle")}
          description={t("lbPaleeAskBody")}
          testId="palee-consent-sheet"
          error={answer.isError ? t("lbPaleeAskFailed") : null}
          footer={
            <div className="flex w-full flex-col gap-2">
              <button
                type="button"
                disabled={answer.isPending}
                onClick={() => answer.mutate("share")}
                className="min-h-11 w-full rounded-full px-4 text-sm font-bold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
              >
                {t("lbPaleeAskShare")}
              </button>
              <button
                type="button"
                disabled={answer.isPending}
                onClick={() => answer.mutate("see_only")}
                className="min-h-11 w-full rounded-full px-4 text-sm font-semibold disabled:opacity-50"
                style={{ color: "var(--text-soft)" }}
              >
                {t("lbPaleeAskSeeOnly")}
              </button>
            </div>
          }
        >
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("lbPaleeAskWhere")}</p>
        </Dialog>
      ) : null}
    </div>
  );
}

function scaleLabel(board: Board, slug: string) {
  return board.options.scales.find((scale) => scale.slug === slug)?.label ?? slug;
}

function chipLabel(chip: LeaderboardChip, t: ReturnType<typeof useTranslations>) {
  switch (chip.kind) {
    case "all":
      return t("lbChipAll");
    case "scope":
      return chip.value === "palee" ? t("lbChipPalee") : t("lbChipMyBox");
    case "division":
      return t(`division_${chip.value}`);
    case "age":
      return ageGroupLabel(chip.value);
    case "scale":
      return chip.label;
  }
}

function Row({
  row,
  scale,
  paleeTotal,
}: {
  row: WorkoutLeaderboardRow;
  scale: string | null;
  /** On the Palee-wide board: how many scores the slice holds. */
  paleeTotal: number | null;
}) {
  const t = useTranslations("TrainingFloor");
  const name = row.me ? t("lbYou") : (row.nickname ?? "?");
  const value = [row.value, row.unit].filter(Boolean).join(" ");
  const fewResults = row.me && row.rank !== null && row.top_percent === null;

  return (
    <li
      className="flex items-center gap-3 rounded-xl px-2 py-1.5"
      style={{ background: row.me ? "var(--panel-raised)" : "transparent" }}
      data-testid={row.me ? "wod-leaderboard-me" : undefined}
    >
      <span className="w-5 text-center font-mono text-sm font-bold" style={{ color: "var(--dim)" }}>{row.rank ?? "–"}</span>
      {row.avatar_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
        <img src={row.avatar_url} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
      ) : (
        <span
          aria-hidden="true"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-extrabold"
          style={{ background: "var(--panel-raised)", color: "var(--text)" }}
        >
          {clubInitials(row.nickname ?? "?")}
        </span>
      )}
      <span className="min-w-0 grow">
        <b className="block truncate text-sm" style={{ color: "var(--text)" }}>
          {name}
          {scale ? <span className="ml-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{scale}</span> : null}
        </b>
        {row.box_name && !(row.me && row.percentile !== null) ? (
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>{row.box_name}</span>
        ) : null}
        {row.me && row.percentile !== null ? (
          <span className="block text-xs" style={{ color: "var(--dim)" }}>
            {paleeTotal !== null
              ? t("lbBetterThanPalee", { percent: row.percentile, count: paleeTotal })
              : t("lbBetterThan", { percent: row.percentile })}
          </span>
        ) : fewResults ? (
          <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("lbFewResults")}</span>
        ) : null}
      </span>
      {row.me && row.top_percent !== null ? (
        <span
          className="shrink-0 rounded-full px-2 py-0.5 text-xs font-bold"
          style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary)" }}
        >
          {t("lbTopPercent", { percent: row.top_percent })}
        </span>
      ) : null}
      <span className="font-mono text-sm" style={{ color: "var(--text)" }}>{value}</span>
    </li>
  );
}
