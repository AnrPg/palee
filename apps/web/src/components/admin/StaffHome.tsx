"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState } from "react";

import { fetchAthletes } from "@/api/admin";
import { fetchPRDossierMembers } from "@/api/admin-users";
import { filterDossierMembers } from "@/components/admin/users/admin-user-profile";
import { fetchCleaningAreas, fetchCoachingRelationships, fetchMyClientStats, startCoachingRelationship } from "@/api/roles";
import { AdminDashboard } from "@/components/admin/AdminDashboard";
import {
  ActionTiles,
  AvatarChips,
  CardAction,
  CardLink,
  CountBadge,
  DashboardCard,
  EmptyNote,
  StatusList,
  type ActionTile,
} from "@/components/admin/DashboardWidgets";
import { roleErrorKey, staffHomeLayout, takeableAthletes } from "@/components/admin/staff-home";
import { formatDateTime } from "@/components/client/format";
import { useSession } from "@/components/session-provider";
import { CleaningLog } from "@/components/staff/CleaningLog";
import { SquadsSection } from "@/components/community/squads/SquadsSection";
import { SetupRecipeCard } from "@/components/admin/setup/SetupRecipeCard";
import { CollectEntry } from "@/components/admin/collect/CollectEntry";
import {
  inputClass,
  inputStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

// The staff home (ADR-103, ADR-135): every staff role gets the dashboard,
// trimmed to what its capabilities open. A janitor's home stays the cleaning
// log. Layout B (ANR, 2026-11-03): set-up first, then «Σήμερα» beside
// «Θέλει προσοχή» (which also holds the coach's queues), the role cards,
// «Οι άνθρωποί σου», and every tool last. See AdminDashboard.

type Membership = ReturnType<typeof useSelectedMembershipRole>["membership"];

const RELATIONSHIPS_KEY = ["staff", "coaching-relationships"] as const;

export function StaffHome() {
  const i18n = useUiTranslations();
  const { membership, isLoading } = useSelectedMembershipRole();
  const layout = staffHomeLayout(membership);

  if (layout.kind === "loading") {
    return (
      <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
        <StatusText tone="muted">{isLoading ? i18n("loading33ce417") : i18n("rhNoGym")}</StatusText>
      </main>
    );
  }

  if (layout.kind === "cleaning") {
    return (
      <>
        {can(membership, "report_inventory") ? <InventoryShortcut /> : null}
        <CleaningLog />
      </>
    );
  }

  const coach = layout.kind === "admin" ? layout.coach : layout.sections.includes("coach");
  const frontDesk = layout.kind === "sections" && layout.sections.includes("front_desk");
  const accountant = layout.kind === "sections" && layout.sections.includes("accountant");
  const has = (capability: string) => can(membership, capability);

  return (
    <AdminDashboard
      membership={membership}
      // ADR-255: a new box picks its kind once (mockup s10 A); first while it is to do.
      setup={<SetupRecipeCard membership={membership} />}
      appointments={coach && has("manage_appointments")}
      coachQueues={coach && has("manage_coaching")}
      people={coach ? <PeopleSection membership={membership} /> : null}
    >
      {/* ADR-272: «Είσπραξη» with Tap to Pay, on a staff phone only. */}
      {has("take_payments") ? <CollectEntry /> : null}
      {frontDesk ? <FrontDeskCard membership={membership} /> : null}
      {accountant ? <AccountsCard membership={membership} /> : null}
      {frontDesk && (has("review_cleaning") || has("record_cleaning")) ? <CleaningStatus /> : null}
    </AdminDashboard>
  );
}

/** The janitor's home is the cleaning log; inventory sits one tap above it (ADR-104). */
function InventoryShortcut() {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  return (
    <div className="px-4 pt-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl justify-end">
        <Link href={adminHref("/admin/inventory", organizationSlug)} className={secondaryButtonClass} style={secondaryButtonStyle}>
          {i18n("invOpenInventory")}
        </Link>
      </div>
    </div>
  );
}

/** The coach's own clients (ADR-100) as avatar chips, with "Take an athlete". */
export function MyClientsSection({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [taking, setTaking] = useState(false);
  const [search, setSearch] = useState("");
  const [showAll, setShowAll] = useState(false);

  const clients = useQuery({
    queryKey: [...RELATIONSHIPS_KEY, { coach: currentUser?.id }],
    enabled: Boolean(token && currentUser?.id),
    queryFn: () => fetchCoachingRelationships(token!, { coachUserId: currentUser!.id }),
  });
  const stats = useQuery({
    queryKey: [...RELATIONSHIPS_KEY, "my-stats", { coach: currentUser?.id }],
    enabled: Boolean(token && currentUser?.id),
    queryFn: () => fetchMyClientStats(token!),
  });
  const athletes = useQuery({
    queryKey: ["staff", "home", "athletes", search.trim()],
    enabled: Boolean(token) && taking,
    queryFn: () => fetchAthletes(token!, search.trim() || undefined),
  });
  const take = useMutation({
    mutationFn: (clientUserId: string) => startCoachingRelationship(token!, clientUserId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: RELATIONSHIPS_KEY });
      await queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
    },
  });

  const relationships = clients.data ?? [];
  const visible = showAll ? relationships : relationships.slice(0, 8);
  const candidates = takeableAthletes(athletes.data?.athletes ?? [], relationships.map((item) => item.client_user_id)).slice(0, 8);
  const canTake = can(membership, "self_assign_athletes");
  const takeError = take.isError ? (roleErrorKey(take.error) ? i18n(roleErrorKey(take.error)!) : localizeError(take.error, i18n)) : null;
  const takeButton = canTake ? (
    <CardAction
      expanded={taking}
      onClick={() => {
        setTaking((value) => !value);
        take.reset();
      }}
    >
      {taking ? i18n("cancel77dfd21") : i18n("rhTakeAthlete")}
    </CardAction>
  ) : null;

  return (
    <DashboardCard
      id="home-my-clients"
      eyebrow={i18n("rhMyClients")}
      badge={clients.data ? <CountBadge value={relationships.length} /> : null}
      action={takeButton}
    >
      <div className="space-y-3">
        {stats.data && relationships.length > 0 ? (
          <dl className="grid grid-cols-2 gap-2">
            {[
              { key: "messages", value: stats.data.coaching_messages_this_week, label: i18n("rhStatCoachingMessages") },
              { key: "awaiting", value: stats.data.awaiting_reply, label: i18n("rhStatAwaitingReply") },
            ].map((stat) => (
              <div key={stat.key} className="flex flex-col-reverse rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                <dt className="text-xs" style={{ color: "var(--dim)" }}>{stat.label}</dt>
                <dd className="text-lg font-semibold tabular-nums" style={{ color: "var(--text)" }}>{stat.value}</dd>
              </div>
            ))}
          </dl>
        ) : null}
        {clients.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : clients.isError ? (
          <StatusText tone="error">{localizeError(clients.error, i18n)}</StatusText>
        ) : relationships.length === 0 ? (
          <EmptyNote>{i18n("rhNoClients")}</EmptyNote>
        ) : (
          <AvatarChips
            people={visible.map((item) => ({
              id: item.id,
              name: item.client_nickname ?? i18n("stfUnknownMember"),
              href: adminHref(`/admin/users/${item.client_user_id}`, organizationSlug),
            }))}
          />
        )}
        {relationships.length > 8 ? (
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setShowAll((value) => !value)}>
            {showAll ? i18n("rhShowFewer") : i18n("rhShowAllClients", { count: relationships.length })}
          </button>
        ) : null}
        {taking ? (
          <div className="space-y-2 rounded-[1.2rem] p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("rhTakeAthleteHelp")}</p>
            <input
              aria-label={i18n("rhSearchAthletes")}
              placeholder={i18n("rhSearchAthletes")}
              className={inputClass}
              style={inputStyle}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            {athletes.isPending ? (
              <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
            ) : athletes.isError ? (
              <StatusText tone="error">{localizeError(athletes.error, i18n)}</StatusText>
            ) : candidates.length === 0 ? (
              <StatusText tone="muted">{i18n("rhNoAthletesToTake")}</StatusText>
            ) : (
              <ul className="grid gap-2">
                {candidates.map((athlete) => (
                  <li key={athlete.id} className="flex items-center justify-between gap-3">
                    <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{athlete.nickname}</span>
                    <button
                      type="button"
                      disabled={take.isPending}
                      className={secondaryButtonClass}
                      style={secondaryButtonStyle}
                      onClick={() => take.mutate(athlete.id)}
                    >
                      {i18n("rhTake")}
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {takeError ? <StatusText tone="error">{takeError}</StatusText> : null}
            {take.isSuccess ? <StatusText tone="success">{i18n("rhAthleteTaken")}</StatusText> : null}
          </div>
        ) : null}
      </div>
    </DashboardCard>
  );
}

/** «Οι άνθρωποί σου»: find any box member, then the coach's clients and groups. */
function PeopleSection({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  return (
    <section id="home-people" aria-labelledby="home-people-title" className="space-y-3">
      <h2 id="home-people-title" className="text-base font-bold" style={{ color: "var(--text)" }}>
        {i18n("shPeopleTitle")}
      </h2>
      <MemberSearch />
      <div className="grid items-stretch gap-6 md:grid-cols-2 md:[&>*:only-child]:col-span-2">
        <MyClientsSection membership={membership} />
        <SquadsSection membership={membership} />
      </div>
    </section>
  );
}

/**
 * ADR-132: every coach of the gym reads members' PRs (ADR-129), while "My
 * clients" lists only their own clients (ADR-100). One search field: nobody
 * is listed until the coach types, and a match opens the member's profile
 * at their PRs.
 */
function MemberSearch() {
  const t = useTranslations("PrSharing");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const [search, setSearch] = useState("");

  const members = useQuery({
    queryKey: ["admin", "pr-members"],
    enabled: Boolean(token),
    queryFn: () => fetchPRDossierMembers(token!),
    staleTime: 60_000,
  });
  const typed = search.trim();
  const list = Array.isArray(members.data?.members) ? members.data.members : [];
  const matches = typed ? filterDossierMembers(list, search).slice(0, 8) : [];

  return (
    <div id="home-member-search" className="space-y-2">
      <label
        className="flex items-center gap-3 rounded-[1.4rem] px-4 py-2 focus-within:ring-2 focus-within:ring-[var(--focus-ring)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>⌕</span>
        <input
          aria-label={i18n("shMemberSearch")}
          placeholder={i18n("shMemberSearch")}
          className="min-w-0 flex-1 bg-transparent py-1.5 text-sm outline-none"
          style={{ color: "var(--text)" }}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
        <span className="hidden shrink-0 text-xs sm:inline" style={{ color: "var(--dim)" }}>
          {i18n("shMemberSearchHint")}
        </span>
      </label>
      {!typed ? null : (
        <div className="rounded-[1.4rem] p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          {members.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : members.isError ? (
            <StatusText tone="error">{t("membersLoadError")}</StatusText>
          ) : matches.length === 0 ? (
            <EmptyNote>{t("membersEmpty")}</EmptyNote>
          ) : (
            <AvatarChips
              people={matches.map((member) => ({
                id: member.id,
                name: member.nickname,
                href: `${adminHref(`/admin/users/${member.id}`, organizationSlug)}#prs`,
              }))}
            />
          )}
        </div>
      )}
    </div>
  );
}

function FrontDeskCard({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  const has = (capability: string) => can(membership, capability);
  const href = (path: string) => adminHref(path, organizationSlug);
  const tiles: ActionTile[] = [
    ...(has("check_in") ? [{ label: i18n("rhArrivalsNow"), href: href("/admin/check-in"), icon: "check" as const }] : []),
    ...(has("invite_clients") ? [{ label: i18n("rhNewClient"), href: href("/admin/finance?tab=members"), icon: "plus" as const }] : []),
    ...(has("take_payments") ? [{ label: i18n("rhSellPackage"), href: href("/admin/finance"), icon: "card" as const }] : []),
    ...(has("take_payments") ? [{ label: i18n("rhTakePayment"), href: href("/admin/finance?tab=queues"), icon: "wallet" as const }] : []),
  ];
  if (tiles.length === 0) return null;
  return (
    <DashboardCard id="home-front-desk" eyebrow={i18n("rhFrontDesk")}>
      <ActionTiles tiles={tiles} />
    </DashboardCard>
  );
}

function CleaningStatus() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const areas = useQuery({
    queryKey: ["staff", "cleaning", "areas"],
    enabled: Boolean(token),
    queryFn: () => fetchCleaningAreas(token!),
  });
  const active = (areas.data ?? []).filter((area) => !area.archived_at);

  return (
    <DashboardCard
      id="home-cleaning-status"
      eyebrow={i18n("rhCleaningStatus")}
      action={<CardLink href={adminHref("/admin/cleaning", organizationSlug)}>{i18n("open6f4789b")}</CardLink>}
    >
      {areas.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : areas.isError ? (
        <StatusText tone="error">{localizeError(areas.error, i18n)}</StatusText>
      ) : active.length === 0 ? (
        <EmptyNote>{i18n("cleanNoAreas")}</EmptyNote>
      ) : (
        <StatusList
          rows={active.map((area) => ({
            id: area.id,
            label: area.name,
            status: area.last_cleaned_at
              ? i18n("rhLastCleaned", { time: formatDateTime(area.last_cleaned_at, locale) })
              : i18n("rhNeverCleaned"),
            tone: area.last_cleaned_at ? "ok" : "warn",
          }))}
        />
      )}
    </DashboardCard>
  );
}

function AccountsCard({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  const has = (capability: string) => can(membership, capability);
  const href = (path: string) => adminHref(path, organizationSlug);
  const tiles: ActionTile[] = [
    ...(has("take_payments") || has("manage_billing")
      ? [
          { label: i18n("rhOverdue"), href: href("/admin/finance?tab=queues"), icon: "file" as const, hint: i18n("rhOverdueHint") },
          { label: i18n("rhCorporateBalances"), href: href("/admin/finance?tab=corporate"), icon: "users" as const },
          { label: i18n("rhDeskPayments"), href: href("/admin/finance?tab=members"), icon: "card" as const, hint: i18n("rhDeskPaymentsHint") },
        ]
      : []),
    ...(has("view_finance_reports") ? [{ label: i18n("rhFinanceReports"), href: href("/admin/metrics/finance"), icon: "chart" as const }] : []),
  ];
  if (tiles.length === 0) return null;
  return (
    <DashboardCard id="home-accounts" eyebrow={i18n("rhAccounts")}>
      <ActionTiles tiles={tiles} />
    </DashboardCard>
  );
}
