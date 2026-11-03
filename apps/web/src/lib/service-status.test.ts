import { describe, expect, it } from "vitest";

import {
  componentTone,
  dayBarColor,
  incidentText,
  lastDays,
  overallTone,
  statusHostRewrite,
  statusViewer,
  maintenanceDueSoon,
  startsLater,
  stripIncident,
  toneColor,
  uptimeOver,
  usesComponent,
} from "@/lib/service-status";

const member = statusViewer({ signedIn: true, memberships: [{ role: "member" }] });
const owner = statusViewer({ signedIn: true, memberships: [{ role: "owner", roles: ["owner", "coach"] }] });
const noBox = statusViewer({ signedIn: true, memberships: [] });
const guest = statusViewer({ signedIn: false, memberships: [] });

describe("service status (ADR-364/366)", () => {
  it("maps every state to a theme colour, never a literal", () => {
    expect(toneColor(componentTone("operational"))).toBe("var(--success)");
    expect(toneColor(componentTone("degraded"))).toBe("var(--warning)");
    expect(toneColor(componentTone("down"))).toBe("var(--danger)");
    expect(toneColor(overallTone("partial_outage"))).toBe("var(--warning)");
    expect(toneColor(overallTone("unknown"))).toBe("var(--dim)");
    expect(dayBarColor("no_data")).toBe("var(--panel-muted)");
    expect(dayBarColor("operational")).toContain("var(--success)");
  });

  it("shows the last 30 or 90 days and their uptime", () => {
    const days = Array.from({ length: 90 }, (_, i) => ({ date: `d${i}`, uptime_percent: i === 89 ? 98 : 100 }));
    expect(lastDays(days, 30)).toHaveLength(30);
    expect(lastDays(days, 30)[29].date).toBe("d89");
    expect(uptimeOver(lastDays(days, 30))).toBe(99.93);
    expect(uptimeOver([{ uptime_percent: null }])).toBeNull();
  });

  it("reads the original in its language and English otherwise", () => {
    const incident = {
      title: "Καθυστερήσεις",
      title_en: "Delays",
      locale: "el",
      en_source: "auto",
      updates: [{ body: "Το ερευνούμε.", body_en: "We are looking into it.", locale: "el", en_source: "auto" }],
    };
    expect(incidentText(incident, "el")).toEqual({ title: "Καθυστερήσεις", body: "Το ερευνούμε.", machine: false });
    expect(incidentText(incident, "de")).toEqual({ title: "Delays", body: "We are looking into it.", machine: true });
    expect(incidentText({ ...incident, title_en: null, updates: [{ body: "x", body_en: null }] }, "de").title).toBe("Καθυστερήσεις");
  });

  it("concerns only the people who use the affected component", () => {
    expect(usesComponent("email", member)).toBe(true);
    expect(usesComponent("payments", member)).toBe(true);
    expect(usesComponent("payments", noBox)).toBe(false);
    expect(usesComponent("fiscal", member)).toBe(false);
    expect(usesComponent("fiscal", owner)).toBe(true);
    expect(usesComponent("app", guest)).toBe(false);
  });

  it("the strip shows an active incident with an impact that concerns the viewer, incidents first", () => {
    const fiscal = { id: "f", kind: "incident", impact: "major", components: ["fiscal"] };
    const quiet = { id: "q", kind: "incident", impact: "none", components: ["app"] };
    const works = { id: "m", kind: "maintenance", impact: "minor", components: ["app"] };
    const email = { id: "e", kind: "incident", impact: "minor", components: ["email"] };
    expect(stripIncident([fiscal, quiet], member)).toBeNull();
    expect(stripIncident([fiscal], owner)?.id).toBe("f");
    expect(stripIncident([works, email], member)?.id).toBe("e");
    expect(stripIncident([works], member)?.id).toBe("m");
    expect(stripIncident([email], guest)).toBeNull();
    expect(stripIncident([{ id: "all", kind: "incident", impact: "critical", components: [] }], noBox)?.id).toBe("all");
    const noComponents = { id: "n", kind: "incident", impact: "major" } as unknown as typeof email;
    expect(stripIncident([noComponents], member)?.id).toBe("n");
  });

  it("planned maintenance enters the strip only in the 24 hours before it starts (ADR-366 amendment)", () => {
    const now = new Date("2026-11-03T10:00:00Z");
    const plan = (id: string, scheduled_for: string, components = ["app"]) => ({ id, kind: "maintenance", impact: "minor", status: "scheduled", components, scheduled_for });
    const in25h = plan("far", "2026-11-04T11:00:00Z");
    const in24h = plan("edge", "2026-11-04T10:00:00Z");
    const in3h = plan("soon", "2026-11-03T13:00:00Z");
    const fiscalSoon = plan("fiscal", "2026-11-03T12:00:00Z", ["fiscal"]);

    expect(maintenanceDueSoon(in25h, now)).toBe(false);
    expect(maintenanceDueSoon(in24h, now)).toBe(true);
    expect(maintenanceDueSoon(in3h, now)).toBe(true);
    expect(maintenanceDueSoon({ kind: "incident", scheduled_for: "2026-11-03T13:00:00Z" }, now)).toBe(false);
    expect(maintenanceDueSoon({ kind: "maintenance", scheduled_for: null }, now)).toBe(false);

    // Earlier than 24 hours ahead: only the status page shows it.
    expect(stripIncident([], member, { upcoming: [in25h], now })).toBeNull();
    // The nearest one that concerns the viewer.
    expect(stripIncident([], member, { upcoming: [in25h, in24h, in3h], now })?.id).toBe("soon");
    expect(stripIncident([], member, { upcoming: [fiscalSoon], now })).toBeNull();
    expect(stripIncident([], owner, { upcoming: [fiscalSoon], now })?.id).toBe("fiscal");
    // An active incident or maintenance still comes first.
    const email = { id: "e", kind: "incident", impact: "minor", components: ["email"], status: "investigating", scheduled_for: null as string | null };
    expect(stripIncident([email], member, { upcoming: [in3h], now })?.id).toBe("e");
    // A day later the far one is due.
    expect(stripIncident([], member, { upcoming: [in25h], now: new Date("2026-11-03T11:00:00Z") })?.id).toBe("far");

    expect(startsLater(in3h, now)).toBe(true);
    expect(startsLater({ ...in3h, status: "in_progress" }, now)).toBe(false);
    expect(startsLater(in3h, new Date("2026-11-03T13:00:01Z"))).toBe(false);
    expect(startsLater(email, now)).toBe(false);
  });

  it("serves the status page at the status host's root only", () => {
    expect(statusHostRewrite("status.palee.app", "/", "status.palee.app")).toBe("/status");
    expect(statusHostRewrite("Status.Palee.app", "/", "status.palee.app")).toBe("/status");
    expect(statusHostRewrite("status.palee.app", "/icon.svg", "status.palee.app")).toBeNull();
    expect(statusHostRewrite("palee.app", "/", "status.palee.app")).toBeNull();
  });
});
