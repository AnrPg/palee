import type { Lead, LeadEvent, LeadStage, LeadTask } from "@/api/leads";
import { OPEN_STAGES } from "@/api/leads";
import { dateKeyInZone } from "@/lib/zoned-time";

/** How urgent a lead's next step is: overdue, due today, later, or none at all. */
export type DueState = "late" | "today" | "later" | "none";

export function dueState(task: Pick<LeadTask, "due_at" | "done_at"> | null | undefined, now: Date, zone: string | null): DueState {
  if (!task || task.done_at) return "none";
  const due = new Date(task.due_at);
  if (due.getTime() < now.getTime()) return "late";
  return dateKeyInZone(due, zone) === dateKeyInZone(now, zone) ? "today" : "later";
}

export type OpenStage = (typeof OPEN_STAGES)[number];

/** The kanban columns: the open stages in order, each with its leads (most urgent first). */
export function columns(leads: Lead[], now: Date, zone: string | null): Array<{ stage: OpenStage; leads: Lead[] }> {
  const rank: Record<DueState, number> = { late: 0, today: 1, none: 2, later: 3 };
  return OPEN_STAGES.map((stage) => ({
    stage,
    leads: leads
      .filter((lead) => lead.stage === stage)
      .sort((a, b) => {
        const byDue = rank[dueState(a.next_task, now, zone)] - rank[dueState(b.next_task, now, zone)];
        if (byDue !== 0) return byDue;
        return b.created_at.localeCompare(a.created_at);
      }),
  }));
}

/** A count per stage, zero for the ones the API left out. */
export function stageCount(counts: Record<string, number> | undefined, stage: LeadStage | "open"): number {
  if (!counts) return 0;
  if (stage === "open") return OPEN_STAGES.reduce((sum, key) => sum + (counts[key] ?? 0), 0);
  return counts[stage] ?? 0;
}

/** A stage a lead may be dragged or switched to by hand (never «Έγινε μέλος»: that needs the profile). */
export function canMoveTo(lead: Pick<Lead, "stage">, stage: LeadStage): boolean {
  if (lead.stage === stage) return false;
  if (lead.stage === "converted") return false;
  return stage !== "converted";
}

/** Two letters for an avatar from any name (Greek too). */
export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  const letters = parts.length === 1 ? [...parts[0]].slice(0, 2) : [[...parts[0]][0], [...parts[parts.length - 1]][0]];
  return letters.join("").toLocaleUpperCase();
}

export type LeadFormErrors = Partial<Record<"name" | "contact" | "email", "required" | "invalid">>;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** The new-lead form: a name and at least one way to reach the person (ADR-344). */
export function validateLeadForm(form: { name: string; email: string; phone: string }): LeadFormErrors {
  const errors: LeadFormErrors = {};
  if (!form.name.trim()) errors.name = "required";
  const email = form.email.trim();
  if (!email && !form.phone.trim()) errors.contact = "required";
  if (email && !EMAIL.test(email)) errors.email = "invalid";
  return errors;
}

/** The enquiry form (ADR-345): a name, a phone or an email, and the contact consent. */
export function validateEnquiry(form: { name: string; contact: string; consent: boolean }) {
  const errors: Partial<Record<"name" | "contact" | "consent", "required" | "invalid">> = {};
  if (!form.name.trim()) errors.name = "required";
  const contact = form.contact.trim();
  if (!contact) errors.contact = "required";
  else if (contact.includes("@") ? !EMAIL.test(contact) : contact.replace(/[^\d]/g, "").length < 6) errors.contact = "invalid";
  if (!form.consent) errors.consent = "required";
  return errors;
}

/** Splits «phone or email» into the field the API expects. */
export function splitContact(contact: string): { email?: string; phone?: string } {
  const value = contact.trim();
  if (!value) return {};
  return value.includes("@") ? { email: value } : { phone: value };
}

/**
 * One history line: the message key under `Leads.event.*` and its values.
 * Who did it and when are shown next to it by the panel (ADR-384).
 */
export function eventLine(event: Pick<LeadEvent, "kind" | "data">): { key: string; values: Record<string, string> } {
  const data = (event.data ?? {}) as Record<string, unknown>;
  const text = (key: string) => (typeof data[key] === "string" ? (data[key] as string) : "");
  switch (event.kind) {
    case "stage_changed":
      return text("to") === "lost"
        ? { key: "lost", values: { reason: text("lost_reason") || "other" } }
        : { key: "stage_changed", values: { stage: text("to") || "new" } };
    case "contacted":
      return { key: "contacted", values: { channel: text("channel") || "phone" } };
    case "note":
      return { key: "note", values: { text: text("text") } };
    case "task_added":
    case "task_done":
      return { key: event.kind, values: { title: text("title") } };
    case "created":
    case "enquired_again":
      return { key: event.kind, values: { source: text("source") || "manual" } };
    case "message_sent":
      return { key: "message_sent", values: { recipe: text("recipe") } };
    default:
      return { key: event.kind, values: {} };
  }
}

/** A `tel:` link the phone can dial, or null. */
export function telHref(phone: string | null | undefined): string | null {
  const digits = (phone ?? "").replace(/[^\d+]/g, "");
  return digits.length >= 6 ? `tel:${digits}` : null;
}
