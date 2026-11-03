"use client";

import { useQueryClient } from "@tanstack/react-query";

import { LoadingLine } from "@/components/client/ClientPage";
import { LeaderboardProfileFields } from "@/components/member-app/me/LeaderboardProfileFields";
import { useLanding, useLeaderboardOptIn } from "@/components/member-app/progress/use-landing";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Whether I appear on my gym's leaderboard (opt-in, brief §4.5), and, once
 * on it, the division and birth year that fair comparison needs (ADR-356).
 */
export function LeaderboardSetting() {
  const i18n = useUiTranslations();
  const landing = useLanding();
  const toggle = useLeaderboardOptIn();
  const optedIn = landing.data?.gamification?.leaderboard.opted_in ?? false;
  const slug = useSelectedMembershipRole().membership?.organization.slug ?? null;
  const queryClient = useQueryClient();

  if (landing.noGym) return null;
  if (landing.isPending) return <LoadingLine />;

  return (
    <div className="space-y-4">
      <p className="text-sm" style={{ color: "var(--muted)" }}>
        {i18n("theLeaderboardIsOptInOnlyYourData3e23cde")}
      </p>
      <button
        type="button"
        aria-pressed={optedIn}
        disabled={toggle.isPending || !landing.data}
        onClick={() =>
          toggle.mutate(!optedIn, { onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["training-floor"] }) })
        }
        className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
        style={optedIn ? { border: "1px solid var(--border)", color: "var(--text)" } : { background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {optedIn ? i18n("leaveLeaderboard834f047") : i18n("joinLeaderboardad480b1")}
      </button>
      {optedIn && slug ? <LeaderboardProfileFields slug={slug} /> : null}
    </div>
  );
}
