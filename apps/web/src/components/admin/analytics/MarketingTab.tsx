"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";

import { fetchAdminChallenges, type AdminChallengeRecord } from "@/api/challenges";
import { fetchPromotionCampaigns } from "@/api/finance";
import { fetchStaffReferrals, staffReferralsKey } from "@/api/referrals";
import { useMarketingAccess } from "@/components/admin/marketing/marketing-access";
import { useStaffPerks } from "@/components/perks/use-perks";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { MARKETING_ROUTES } from "@/lib/marketing-routes";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { localToday, perkPhase } from "@/lib/perks/validity";

function runsNow(challenge: Pick<AdminChallengeRecord, "starts_at" | "ends_at">, now = Date.now()) {
  return new Date(challenge.starts_at).getTime() <= now && new Date(challenge.ends_at).getTime() >= now;
}

type Tile = {
  id: string;
  title: string;
  description: string;
  href: string;
  /** One live figure, once it has loaded; the description shows until then. */
  stat?: string | null;
  /** The area lives in Οικονομικά (Πακέτα): the tile says so. */
  inFinance?: boolean;
};

/**
 * Στατιστικά & Μάρκετινγκ › Μάρκετινγκ (ANR 2026-11-04, option A): the home of
 * challenges, the box's promotions, partner perks and referrals, each a tile
 * with one live number from the list it opens, plus a link to Πακέτα, which
 * stay in Οικονομικά. A tile shows only to someone who may open the area.
 */
export function MarketingTab() {
  const t = useTranslations("MarketingHub");
  const i18n = useUiTranslations();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const access = useMarketingAccess();
  const opens = {
    challenges: access.opens("challenges"),
    promotions: access.opens("promotions"),
    perks: access.opens("perks"),
    referrals: access.opens("referrals"),
  };

  // The same keys as the pages they open, so opening a tile starts from the cache.
  const challenges = useQuery({
    queryKey: ["admin", "challenges"],
    enabled: Boolean(token) && opens.challenges,
    queryFn: () => fetchAdminChallenges(token),
  });
  const promotions = useQuery({
    queryKey: ["admin", "finance", "promotions"],
    enabled: Boolean(token) && opens.promotions,
    queryFn: () => fetchPromotionCampaigns(token),
  });
  const perks = useStaffPerks(opens.perks);
  const referrals = useQuery({
    queryKey: staffReferralsKey("review"),
    enabled: Boolean(token) && opens.referrals,
    queryFn: () => fetchStaffReferrals(token, "review"),
  });

  const running = (challenges.data?.challenges ?? []).filter((challenge) => runsNow(challenge));
  const today = localToday();
  const livePerks = (perks.data ?? []).filter((perk) => perkPhase(perk, today) === "published");

  const candidates: Array<Tile | false> = [
    opens.challenges && {
      id: "challenges",
      title: i18n("challengesff38765"),
      description: i18n("manageSeasonalEngagementCampaignsAndReviewParticipationdf0bc50"),
      href: MARKETING_ROUTES.challenges,
      stat: challenges.data
        ? t("challengesStat", {
            active: running.length,
            participants: running.reduce((sum, challenge) => sum + Number(challenge.progress_summary?.participants ?? 0), 0),
          })
        : null,
    },
    opens.promotions && {
      id: "promotions",
      title: t("boxPromotions"),
      description: i18n("createAndManagePromotionalOffers46d33bb"),
      href: MARKETING_ROUTES.promotions,
      stat: promotions.data
        ? t("promotionsStat", { active: promotions.data.promotion_campaigns.filter((campaign) => campaign.active !== false).length })
        : null,
    },
    opens.perks && {
      id: "perks",
      title: t("partnerPerks"),
      description: t("partnerPerksDescription"),
      href: MARKETING_ROUTES.perks,
      stat: perks.data
        ? t("perksStat", { active: livePerks.length, uses: (perks.data ?? []).reduce((sum, perk) => sum + Number(perk.uses_count ?? 0), 0) })
        : null,
    },
    opens.referrals && {
      id: "referrals",
      title: i18n("referrals2b0e3a3"),
      description: i18n("reviewReferralActivityAndRewardActions8ea1271"),
      href: MARKETING_ROUTES.referrals,
      stat: referrals.data ? t("referralsStat", { count: Number(referrals.data.stats?.qualified ?? 0) }) : null,
    },
    access.opensFinance && {
      id: "packages",
      title: i18n("packages0a99901"),
      description: i18n("manageThePackagesUsedByMembershipsAndEntitlementsb466c1f"),
      href: "/admin/finance?tab=packages",
      inFinance: true,
    },
  ];
  const tiles = candidates.filter((tile): tile is Tile => tile !== false);

  if (!access.ready) return null;
  if (tiles.length === 0) {
    return (
      <p className="rounded-2xl px-5 py-4 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--muted)" }}>
        {t("empty")}
      </p>
    );
  }

  return (
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" data-testid="marketing-tiles">
      {tiles.map((tile) => (
        <Link
          key={tile.id}
          data-testid={`marketing-tile-${tile.id}`}
          className="group flex flex-col rounded-[2rem] p-6 transition-transform hover:-translate-y-0.5"
          href={adminHref(tile.href, slug)}
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{tile.title}</p>
          {tile.stat ? (
            <p className="mt-2 text-sm font-semibold" style={{ color: "var(--primary)" }} data-testid={`marketing-stat-${tile.id}`}>
              {tile.stat}
            </p>
          ) : null}
          <p className="mt-2 flex-1 text-sm leading-6" style={{ color: "var(--muted)" }}>{tile.description}</p>
          <p className="mt-5 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {tile.inFinance ? t("inFinance") : i18n("opencf9b770")}{" "}
            <span aria-hidden="true" className="inline-block transition-transform group-hover:translate-x-1 rtl:rotate-180 rtl:group-hover:-translate-x-1">→</span>
          </p>
        </Link>
      ))}
    </section>
  );
}
