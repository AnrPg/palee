// ADR-366, W7 screen 2: the platform console's «Νέο πρόβλημα ή συντήρηση»
// form. Pure: the draft, its errors and what is sent.

import type { StatusComponentKey } from "@/lib/service-status";

export type IncidentKind = "incident" | "maintenance";
export type Severity = "minor" | "major" | "critical";

/** The English preview: a machine translation the publisher may correct. */
export type EnglishPreview =
  | { state: "idle" }
  | { state: "pending"; key: string }
  | { state: "failed"; key: string }
  /** The text is already English: nothing to translate. */
  | { state: "same"; key: string; locale: string }
  | { state: "ready"; key: string; locale: string | null; title: string; body: string; edited: boolean };

export type IncidentDraft = {
  kind: IncidentKind;
  components: StatusComponentKey[];
  severity: Severity;
  title: string;
  body: string;
  /** "YYYY-MM-DDTHH:MM" on the publisher's clock (maintenance only). */
  from: string;
  until: string;
  english: EnglishPreview;
};

export const EMPTY_DRAFT: IncidentDraft = {
  kind: "incident",
  components: [],
  severity: "minor",
  title: "",
  body: "",
  from: "",
  until: "",
  english: { state: "idle" },
};

export type DraftErrors = Partial<Record<"title" | "body" | "window" | "englishTitle" | "englishBody", string>>;

/** What a translation was made for; a different key means the text changed since. */
export function translationKey(title: string, body: string) {
  return `${title.trim()}\u0000${body.trim()}`;
}

/** Whether the text needs a (new) translation. */
export function needsTranslation(draft: Pick<IncidentDraft, "title" | "body" | "english">, withTitle = true) {
  if (draft.body.trim() === "" || (withTitle && draft.title.trim().length < 3)) return false;
  const english = draft.english;
  if (english.state === "idle") return true;
  if (english.state === "ready" && english.edited) return false;
  return english.key !== translationKey(withTitle ? draft.title : "", draft.body);
}

/** The errors of a draft, as message keys; empty when it can be published. */
export function draftErrors(draft: IncidentDraft, withTitle = true): DraftErrors {
  const errors: DraftErrors = {};
  const title = draft.title.trim();
  if (withTitle && (title.length < 3 || title.length > 140)) errors.title = "errorTitle";
  const body = draft.body.trim();
  if (body.length < 1 || body.length > 2000) errors.body = "errorBody";
  if (withTitle && draft.kind === "maintenance") {
    const from = Date.parse(draft.from);
    const until = Date.parse(draft.until);
    if (!draft.from || !draft.until || Number.isNaN(from) || Number.isNaN(until)) errors.window = "errorWindowMissing";
    else if (until <= from) errors.window = "errorWindowOrder";
  }
  if (draft.english.state === "ready") {
    if (withTitle) {
      const englishTitle = draft.english.title.trim();
      if (englishTitle.length < 3 || englishTitle.length > 140) errors.englishTitle = "errorTitle";
    }
    const englishBody = draft.english.body.trim();
    if (englishBody.length < 1 || englishBody.length > 2000) errors.englishBody = "errorBody";
  }
  return errors;
}

function translationFields(english: EnglishPreview, withTitle: boolean) {
  if (english.state === "same") return { locale: english.locale };
  if (english.state !== "ready") return {};
  return {
    ...(english.locale ? { locale: english.locale } : {}),
    ...(withTitle ? { title_en: english.title.trim() } : {}),
    body_en: english.body.trim(),
    en_source: english.edited ? ("edited" as const) : ("auto" as const),
  };
}

/** The body of `POST /api/platform/status/incidents`. Untranslated when the translation failed. */
export function incidentPayload(draft: IncidentDraft) {
  const base = {
    kind: draft.kind,
    title: draft.title.trim(),
    body: draft.body.trim(),
    components: draft.components,
    notify: true,
    ...translationFields(draft.english, true),
  };
  if (draft.kind === "maintenance") {
    return {
      ...base,
      impact: "minor" as const,
      scheduled_for: new Date(draft.from).toISOString(),
      scheduled_until: new Date(draft.until).toISOString(),
    };
  }
  return { ...base, impact: draft.severity };
}

/** The body of `POST .../incidents/:id/updates`: a new step with its note. */
export function updatePayload(draft: Pick<IncidentDraft, "body" | "english">, status: string) {
  return { status, body: draft.body.trim(), notify: true, ...translationFields(draft.english, false) };
}

/** The steps a person may pick next for an open incident or maintenance. */
export function nextStatuses(kind: string): string[] {
  return kind === "maintenance" ? ["in_progress", "completed"] : ["investigating", "identified", "monitoring", "resolved"];
}

/** «Ιστορικό» counts: closed incidents and maintenance in the window. */
export function historyCounts(incidents: Array<{ kind: string; resolved_at: string | null }>) {
  const closed = incidents.filter((incident) => incident.resolved_at);
  return {
    incidents: closed.filter((incident) => incident.kind === "incident").length,
    maintenance: closed.filter((incident) => incident.kind === "maintenance").length,
  };
}
