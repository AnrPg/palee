"use client";

import { useTranslations } from "next-intl";

import type { ClassVisitPerson, VisitBadge, VisitVia } from "@/api/training-floor";

const BADGE_KEYS: Record<VisitBadge, string> = {
  first_visit: "badgeFirstVisit",
  first_in_class_type: "badgeFirstInClassType",
  guest: "badgeGuest",
  trial: "badgeTrial",
  brought_by_member: "badgeBroughtByMember",
  came_via_event: "badgeViaEvent",
  came_via_referral: "badgeViaReferral",
};

const BADGE_TONE: Partial<Record<VisitBadge, string>> = {
  first_visit: "var(--primary)",
  trial: "var(--success)",
  guest: "var(--warning)",
};

function Chip({ label, tone = "var(--muted)" }: { label: string; tone?: string }) {
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[11px] font-bold"
      style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}
    >
      {label}
    </span>
  );
}

/** «Ήρθε μέσω event» / «Ήρθε μέσω Μαρίας» (ADR-359 `via`). */
export function viaLabel(via: VisitVia | null | undefined, t: ReturnType<typeof useTranslations>): string | null {
  if (!via) return null;
  if (via.kind === "event") return t("viaEvent");
  return via.by_nickname ? t("viaMember", { name: via.by_nickname }) : t("viaReferral");
}

/**
 * The ADR-359 badges of one person (ANR mockup e1): words, never icons, so
 * they read from across the floor. `skip` leaves out what the row already says.
 */
export function VisitBadgeChips({
  badges,
  via,
  skip = [],
}: {
  badges: readonly VisitBadge[];
  via?: VisitVia | null;
  skip?: readonly VisitBadge[];
}) {
  const t = useTranslations("TrainingFloor");
  const shown = badges.filter((badge) => !skip.includes(badge) && badge !== "came_via_event" && badge !== "came_via_referral");
  const viaText = viaLabel(via, t);
  if (shown.length === 0 && !viaText) return null;
  return (
    <span className="inline-flex flex-wrap items-center gap-1" data-testid="visit-badges">
      {shown.map((badge) => (
        <Chip key={badge} label={t(BADGE_KEYS[badge])} tone={BADGE_TONE[badge]} />
      ))}
      {viaText ? <Chip label={viaText} /> : null}
    </span>
  );
}

/**
 * «Νέοι σήμερα» at the top of the class list (ANR mockup e1 B): who to
 * welcome, before the coach scans the whole roster. The roster below keeps
 * the same badges.
 */
export function NewTodayCard({ people, nameFor }: { people: ClassVisitPerson[]; nameFor: (person: ClassVisitPerson) => string }) {
  const t = useTranslations("TrainingFloor");
  if (people.length === 0) return null;
  return (
    <section
      className="rounded-[1.2rem] p-4"
      style={{ background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" }}
      aria-label={t("newTodayTitle", { count: people.length })}
      data-testid="new-today"
    >
      <h4 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("newTodayTitle", { count: people.length })}</h4>
      <ul className="mt-2 flex flex-col gap-2">
        {people.map((person) => (
          <li key={person.booking_id} className="flex flex-wrap items-center gap-2 text-sm">
            <b style={{ color: "var(--text)" }}>{nameFor(person)}</b>
            <VisitBadgeChips badges={person.badges} via={person.via} />
          </li>
        ))}
      </ul>
    </section>
  );
}
