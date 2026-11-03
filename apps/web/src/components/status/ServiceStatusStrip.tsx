"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchStatusOverview } from "@/api/service-status";
import { useSession } from "@/components/session-provider";
import { useOrganizationMemberships } from "@/lib/organization-slug";
import { incidentText, startsLater, statusViewer, stripIncident, toneColor } from "@/lib/service-status";

import { STATUS_QUERY_KEY } from "./StatusPage";

/** Pages where the strip never shows: the status page itself and full-screen canvases. */
const HIDDEN = [/^\/status(?:\/|$)/, /^\/login(?:\/|$)/, /^\/b(?:\/|$)/, /^\/tv(?:\/|$)/, /^\/admin\/check-in\/(?:door|poster)\//];

/**
 * ADR-366, W7 screen 1: a strip inside the app while an incident is active,
 * only for people who use the affected component (members too). No close
 * button; it goes away by itself once the incident is resolved. A planned
 * maintenance joins it only in the 24 hours before it starts (and while it
 * runs); earlier it is on the status page only (ADR-366 amendment).
 * `now` is injected by tests.
 */
export function ServiceStatusStrip({ now = () => new Date() }: { now?: () => Date } = {}) {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const pathname = usePathname();
  const { currentUser } = useSession();
  const memberships = useOrganizationMemberships();
  const signedIn = Boolean(currentUser);
  const hidden = HIDDEN.some((pattern) => pattern.test(pathname.replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/"));

  const overview = useQuery({
    queryKey: STATUS_QUERY_KEY,
    queryFn: ({ signal }) => fetchStatusOverview(signal),
    enabled: signedIn && !hidden,
    refetchInterval: 60_000,
    staleTime: 30_000,
  });

  if (!signedIn || hidden || !overview.data) return null;
  const viewer = statusViewer({
    signedIn,
    memberships: Array.isArray(memberships.data) ? memberships.data : [],
  });
  // The strip sits in the root layout: a malformed answer must hide it, never break every page.
  const active = Array.isArray(overview.data.active) ? overview.data.active : [];
  const upcoming = Array.isArray(overview.data.upcoming) ? overview.data.upcoming : [];
  const at = now();
  const incident = stripIncident(active, viewer, { upcoming, now: at });
  if (!incident) return null;

  const text = incidentText(incident, locale);
  const later = startsLater(incident, at) && incident.scheduled_for ? new Date(incident.scheduled_for) : null;
  const tone = incident.kind === "maintenance" ? "info" : incident.impact === "minor" ? "warn" : "down";
  const color = toneColor(tone);

  return (
    <div className="px-4 sm:px-6">
      <div
        role="status"
        data-testid="service-status-strip"
        className="mx-auto mt-3 flex max-w-6xl items-center gap-3 rounded-2xl border px-4 py-2.5 text-sm"
        style={{
          background: `color-mix(in srgb, ${color} 14%, var(--panel))`,
          borderColor: `color-mix(in srgb, ${color} 40%, var(--border))`,
          color: "var(--text)",
        }}
      >
        <span aria-hidden style={{ color }}>
          ●
        </span>
        <span className="min-w-0 flex-1">
          <b>{text.title}.</b>{" "}
          {later ? `${t("stripStarts", { when: later.toLocaleString(locale, { weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }) })} ` : null}
          {text.body}
        </span>
        <Link href="/status" className="shrink-0 font-semibold" style={{ color: "var(--primary)" }}>
          {t("stripDetails")}
        </Link>
      </div>
    </div>
  );
}
