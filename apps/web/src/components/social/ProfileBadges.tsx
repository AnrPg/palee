"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPersonBadges, personKey, type PersonProfile } from "@/api/social";
import { badgeDescription, badgeMark, badgeTier } from "@/components/member-app/progress/badges";
import { useSession } from "@/components/session-provider";
import { LockedNote } from "@/components/social/SocialBits";
import { postsLockKey } from "@/components/social/social-model";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-554: the profile's «Διακρίσεις» tab, a three-wide grid of discs, newest
 * first. The owner always sees them; others only while they follow the
 * owner, who chose to show the tab (the API and RLS decide; `locked` says why).
 */
export function ProfileBadges({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const badges = useQuery({
    queryKey: [...personKey(profile.id), "badges"],
    enabled: Boolean(token),
    queryFn: () => fetchPersonBadges(token!, profile.id),
  });

  if (badges.isPending) return <p className="px-4" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  const list = badges.data?.badges ?? [];
  const lock = postsLockKey(profile);
  if (badges.data?.locked && lock)
    return (
      <div className="px-4">
        <LockedNote textKey={lock} />
      </div>
    );
  if (list.length === 0)
    return (
      <p className="mx-4 rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
        {profile.is_me ? t("myBadgesNone") : t("badgesNone")}
      </p>
    );

  return (
    <ul className="grid grid-cols-3 gap-x-2 gap-y-4 px-4 py-2" data-testid="profile-badges">
      {list.map((badge) => {
        const description = badgeDescription(badge.badge_key, i18n);
        const earned = new Date(badge.earned_at).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });
        return (
          <li key={badge.id} className="flex min-w-0 flex-col items-center gap-1 text-center">
            <span
              aria-hidden="true"
              data-tier={badgeTier(badge.badge_key)}
              className="flex size-14 items-center justify-center rounded-full text-base font-extrabold tabular-nums"
              style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
            >
              {badgeMark(badge.badge_key)}
            </span>
            <span className="line-clamp-2 text-xs font-semibold" style={{ color: "var(--text)" }}>{description}</span>
            <span className="text-[11px]" style={{ color: "var(--dim)" }}>{earned}</span>
          </li>
        );
      })}
    </ul>
  );
}
