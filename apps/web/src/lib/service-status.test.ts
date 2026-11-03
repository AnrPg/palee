import { describe, expect, it } from "vitest";

import {
  componentTone,
  dayBarColor,
  incidentText,
  lastDays,
  overallTone,
  statusHostRewrite,
  statusViewer,
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

  it("serves the status page at the status host's root only", () => {
    expect(statusHostRewrite("status.palee.app", "/", "status.palee.app")).toBe("/status");
    expect(statusHostRewrite("Status.Palee.app", "/", "status.palee.app")).toBe("/status");
    expect(statusHostRewrite("status.palee.app", "/icon.svg", "status.palee.app")).toBeNull();
    expect(statusHostRewrite("palee.app", "/", "status.palee.app")).toBeNull();
  });
});
