import { describe, expect, it } from "vitest";

import {
  EMPTY_DRAFT,
  draftErrors,
  historyCounts,
  incidentPayload,
  needsTranslation,
  nextStatuses,
  translationKey,
  updatePayload,
  type IncidentDraft,
} from "@/lib/status-console";

const draft: IncidentDraft = {
  ...EMPTY_DRAFT,
  components: ["email"],
  title: "Καθυστερήσεις στα email",
  body: "Τα αποδεικτικά φεύγουν με καθυστέρηση.",
};
const key = translationKey(draft.title, draft.body);

describe("status console form (ADR-366)", () => {
  it("translates once the text is written, again when it changes, never over a correction", () => {
    expect(needsTranslation({ ...draft, body: "" })).toBe(false);
    expect(needsTranslation(draft)).toBe(true);
    const ready = { state: "ready" as const, key, locale: "el", title: "Email delays", body: "Receipts are late.", edited: false };
    expect(needsTranslation({ ...draft, english: ready })).toBe(false);
    expect(needsTranslation({ ...draft, body: "Νέο κείμενο", english: ready })).toBe(true);
    expect(needsTranslation({ ...draft, body: "Νέο κείμενο", english: { ...ready, edited: true } })).toBe(false);
    expect(needsTranslation({ ...draft, english: { state: "failed", key } })).toBe(false);
  });

  it("keeps errors inside the form, field by field", () => {
    expect(draftErrors(draft)).toEqual({});
    expect(draftErrors({ ...draft, title: "ab", body: " " })).toEqual({ title: "errorTitle", body: "errorBody" });
    expect(draftErrors({ ...draft, kind: "maintenance" }).window).toBe("errorWindowMissing");
    expect(
      draftErrors({ ...draft, kind: "maintenance", from: "2026-11-03T03:00", until: "2026-11-03T02:00" }).window,
    ).toBe("errorWindowOrder");
    expect(
      draftErrors({ ...draft, english: { state: "ready", key, locale: "el", title: "ab", body: "", edited: true } }),
    ).toEqual({ englishTitle: "errorTitle", englishBody: "errorBody" });
    expect(draftErrors({ ...draft, title: "" }, false)).toEqual({});
  });

  it("sends the source language and the English copy, marked auto or edited", () => {
    const english = { state: "ready" as const, key, locale: "el", title: " Email delays ", body: "Late.", edited: false };
    expect(incidentPayload({ ...draft, severity: "major", english })).toEqual({
      kind: "incident",
      title: "Καθυστερήσεις στα email",
      body: "Τα αποδεικτικά φεύγουν με καθυστέρηση.",
      components: ["email"],
      notify: true,
      impact: "major",
      locale: "el",
      title_en: "Email delays",
      body_en: "Late.",
      en_source: "auto",
    });
    expect(updatePayload({ body: "Λύθηκε.", english: { ...english, edited: true } }, "resolved")).toEqual({
      status: "resolved",
      body: "Λύθηκε.",
      notify: true,
      locale: "el",
      body_en: "Late.",
      en_source: "edited",
    });
  });

  it("publishes untranslated when the translation failed, and English without a copy", () => {
    const failed = incidentPayload({ ...draft, english: { state: "failed", key } });
    expect(failed).not.toHaveProperty("title_en");
    expect(failed).not.toHaveProperty("locale");
    expect(incidentPayload({ ...draft, english: { state: "same", key, locale: "en" } })).toMatchObject({ locale: "en" });
  });

  it("a maintenance sends its window in UTC with a minor impact", () => {
    const payload = incidentPayload({ ...draft, kind: "maintenance", from: "2026-11-03T02:00", until: "2026-11-03T02:30" });
    expect(payload).toMatchObject({ kind: "maintenance", impact: "minor" });
    expect(Date.parse((payload as { scheduled_until: string }).scheduled_until) - Date.parse((payload as { scheduled_for: string }).scheduled_for)).toBe(30 * 60_000);
  });

  it("offers the next steps and counts the history", () => {
    expect(nextStatuses("incident")).toEqual(["investigating", "identified", "monitoring", "resolved"]);
    expect(nextStatuses("maintenance")).toEqual(["in_progress", "completed"]);
    expect(
      historyCounts([
        { kind: "incident", resolved_at: "x" },
        { kind: "incident", resolved_at: null },
        { kind: "maintenance", resolved_at: "y" },
      ]),
    ).toEqual({ incidents: 1, maintenance: 1 });
  });
});
