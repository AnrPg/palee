"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { CountBadge } from "@/components/buddy/BuddyBits";
import { activeBuddies, recipientNames, unreadTotal } from "@/components/buddy/buddy-model";
import { useBuddies } from "@/components/buddy/use-buddies";
import { HubList, HubListRow } from "@/components/member-app/HubParts";
import { useOpenConsole } from "@/components/member-app/me/use-open-console";
import { usePasswordResets } from "@/components/member-app/me/use-password-resets";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { useFeatureAtAnyBusiness } from "@/lib/use-business-features";

/**
 * ADR-554 (2A): the ☰ on your own profile, the only thing on Εγώ that others
 * don't see. It opens «Μόνο για σένα», the things you do rather than show:
 * Φέρε φίλο (when a box runs referrals) · Φιλαράκι στήριξης · Πληρωμές &
 * αποδείξεις · Ρυθμίσεις · Βοήθεια & ξενάγηση · (staff) Διαχείριση ·
 * Αποσύνδεση. Language, profiles, sharing & visibility, connected devices and
 * the per-club notifications live in Ρυθμίσεις (ANR's comment on the
 * mockup). A dot on the ☰ says something inside waits for you.
 */
export function MeSheetButton() {
  const t = useTranslations("MemberApp");
  const [open, setOpen] = useState(false);
  const buddies = useBuddies();
  const resets = usePasswordResets();
  const waiting = unreadTotal(buddies.data) + resets.toAct;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={waiting > 0 ? t("meOnlyYouWaiting", { count: waiting }) : t("meOnlyYou")}
        aria-haspopup="dialog"
        className="relative flex size-11 shrink-0 items-center justify-center rounded-full"
        style={{ color: "var(--text)" }}
        data-testid="me-sheet-button"
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <path d="M4 7h16M4 12h16M4 17h16" />
        </svg>
        {waiting > 0 ? (
          <span aria-hidden="true" className="absolute right-2 top-2 size-2 rounded-full" style={{ background: "var(--danger)" }} />
        ) : null}
      </button>
      {open ? <MeSheet onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function MeSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("MemberApp");
  const tBuddy = useTranslations("Buddy");
  const buddies = useBuddies();
  const buddyNames = recipientNames(activeBuddies(buddies.data), tBuddy("someone"));
  const buddyUnread = unreadTotal(buddies.data);
  const { signOut } = useSession();
  const { memberships } = useSelectedMembershipRole();
  const referralsAnywhere = useFeatureAtAnyBusiness(
    memberships.map((entry) => entry.organization.slug),
    "referrals",
  );
  const { hasBillingProviders } = useHasBillingProviders();
  const resets = usePasswordResets();
  const openConsole = useOpenConsole();

  return (
    <Dialog title={t("meOnlyYou")} description={t("meOnlyYouHint")} onClose={onClose} size="md" testId="me-sheet">
      <div className="flex flex-col gap-4">
        <HubList>
          {/* ADR-470: only when one of my boxes runs a referral programme. */}
          {referralsAnywhere ? <HubListRow href="/me/referrals" label={t("meReferrals")} detail={t("meReferralsHint")} /> : null}
          <HubListRow
            href="/me/buddy"
            label={tBuddy("title")}
            detail={buddyNames || tBuddy("rowHint")}
            badge={<CountBadge count={buddyUnread} label={tBuddy("unreadCount", { count: buddyUnread })} />}
          />
          {/* Only for clients of a gym or coach; staff use the console. */}
          {hasBillingProviders ? <HubListRow href="/me/payments" label={t("mePayments")} detail={t("mePaymentsHint")} /> : null}
          <HubListRow href="/me/settings" label={t("meSettings")} detail={t("meSettingsHint")} />
          <HubListRow
            href="/me/help"
            label={t("meHelp")}
            detail={t("meHelpHint")}
            badge={resets.toAct > 0 ? <CountBadge count={resets.toAct} label={t("meHelpResetsWaiting", { count: resets.toAct })} /> : null}
          />
          {/* ADR-196 (amended): staff switch back to the console in one tap. */}
          {openConsole ? <HubListRow onClick={openConsole} label={t("meConsole")} detail={t("meConsoleHint")} /> : null}
        </HubList>
        <button
          type="button"
          onClick={() => signOut()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ color: "var(--danger)", border: "1px solid var(--border)" }}
        >
          {t("signOut")}
        </button>
      </div>
    </Dialog>
  );
}
