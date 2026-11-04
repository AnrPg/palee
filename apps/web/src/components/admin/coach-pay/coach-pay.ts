import type {
  AdjustmentBody,
  AdjustmentKind,
  AmountBasis,
  PayGroup,
  PayItem,
  PayItemBody,
  PayItemLineBody,
  PayLine,
  PayPeriodStatus,
  PayPeriodSummary,
  PayRole,
  PayRule,
  PayRuleBody,
  PayRuleKind,
} from "@/api/coach-pay";

/*
 * «Αμοιβές coaches» (ADR-341, ADR-382; mockup W1 s4–s6), the pure parts:
 * rules read as sentences, the people list where someone without a rule
 * stands out, the rule and line forms with their errors, one primary action
 * per period status, and the gross/net subtotals. Amounts are integer cents.
 */

export type Sentence = { key: string; values: Record<string, string | number> };
export type Money = (cents: number) => string;

export const RULE_KINDS: PayRuleKind[] = ["per_class", "per_attendee", "per_session", "percent_of_sales", "fixed"];
export const SALES_SCOPES = ["personal_training", "sold_by", "own_clients", "box_all"] as const;
export type SalesScope = (typeof SALES_SCOPES)[number];
export const COUNT_STATUSES = ["attended", "late_cancel", "no_show"] as const;
export type CountStatus = (typeof COUNT_STATUSES)[number];
export const FREQUENCIES = ["monthly", "weekly", "daily"] as const;
export type Frequency = (typeof FREQUENCIES)[number];
export const PAY_ROLES: PayRole[] = ["owner", "admin", "head_coach", "coach", "front_desk", "accountant", "janitor"];

/** «15,00 € ανά τμήμα με 3+ αθλητές»: one rule as the owner says it. */
export function ruleSentence(rule: Pick<PayRule, "kind" | "amount_cents" | "percent_bps" | "min_attendees" | "sales_scope" | "frequency" | "count_statuses">, money: Money, percent: (bps: number) => string): Sentence {
  const amount = money(rule.amount_cents ?? 0);
  switch (rule.kind) {
    case "per_class":
      return rule.min_attendees > 0
        ? { key: "rulePerClassMin", values: { amount, min: rule.min_attendees } }
        : { key: "rulePerClass", values: { amount } };
    case "per_attendee":
      return { key: "rulePerAttendee", values: { amount } };
    case "per_session":
      return { key: "rulePerSession", values: { amount } };
    case "percent_of_sales":
      return { key: `rulePercent_${rule.sales_scope ?? "personal_training"}`, values: { percent: percent(rule.percent_bps ?? 0) } };
    case "fixed":
      return { key: `ruleFixed_${rule.frequency ?? "monthly"}`, values: { amount } };
  }
}

/** Active rules: not archived and not ended before `today` (gym-local ISO date). */
export function activeRules(rules: PayRule[], today: string): PayRule[] {
  return rules.filter((rule) => !rule.archived_at && (!rule.ends_on || rule.ends_on >= today));
}

export type PayPerson = { userId: string; name: string; rules: PayRule[] };

/**
 * Mockup s4 A: everyone who can be paid, with their rules. Staff come from
 * the box's staff list; anyone else who holds a rule (front desk, cleaning)
 * joins them. People without a rule sort last, so they stand out together.
 */
export function payPeople(staff: Array<{ id: string; name: string | null }>, rules: PayRule[], unnamed: string): PayPerson[] {
  const people = new Map<string, PayPerson>();
  for (const member of staff) people.set(member.id, { userId: member.id, name: member.name || unnamed, rules: [] });
  for (const rule of rules) {
    const person = people.get(rule.coach_user_id) ?? { userId: rule.coach_user_id, name: rule.coach_name || unnamed, rules: [] };
    person.rules.push(rule);
    people.set(rule.coach_user_id, person);
  }
  return [...people.values()].sort((a, b) => {
    if ((a.rules.length === 0) !== (b.rules.length === 0)) return a.rules.length === 0 ? 1 : -1;
    return a.name.localeCompare(b.name);
  });
}

// ── The rule form ───────────────────────────────────────────────────────────

export type RuleDraft = {
  kind: PayRuleKind;
  amount: string;
  percent: string;
  minAttendees: string;
  countStatuses: CountStatus[];
  salesScope: SalesScope;
  frequency: Frequency;
  startsOn: string;
  endsOn: string;
  basis: AmountBasis;
  note: string;
};

export type RuleField = "amount" | "percent" | "minAttendees" | "countStatuses" | "startsOn" | "endsOn" | "note";
export type RuleErrors = Partial<Record<RuleField, string>>;

export function emptyRuleDraft(today: string): RuleDraft {
  return {
    kind: "per_class",
    amount: "",
    percent: "",
    minAttendees: "",
    countStatuses: ["attended", "late_cancel"],
    salesScope: "personal_training",
    frequency: "monthly",
    startsOn: today,
    endsOn: "",
    basis: "gross",
    note: "",
  };
}

export function ruleDraftFrom(rule: PayRule): RuleDraft {
  return {
    kind: rule.kind,
    amount: rule.amount_cents ? (rule.amount_cents / 100).toFixed(2) : "",
    percent: rule.percent_bps ? String(rule.percent_bps / 100) : "",
    minAttendees: rule.min_attendees > 0 ? String(rule.min_attendees) : "",
    countStatuses: rule.count_statuses.length > 0 ? [...rule.count_statuses] : ["attended"],
    salesScope: (rule.sales_scope ?? "personal_training") as SalesScope,
    frequency: (rule.frequency ?? "monthly") as Frequency,
    startsOn: rule.starts_on,
    endsOn: rule.ends_on ?? "",
    basis: rule.amount_basis,
    note: rule.note ?? "",
  };
}

/** «15», «15,5», «-20,00» → cents (sign allowed only with `signed`); empty or anything else → null. */
export function parseCents(text: string, signed = false): number | null {
  const clean = text.trim().replace(/[€$£\s]/g, "").replace(",", ".");
  const pattern = signed ? /^-?\d{1,6}(\.\d{1,2})?$/ : /^\d{1,6}(\.\d{1,2})?$/;
  if (!pattern.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

/** «40» or «12,5» → basis points; empty or anything else → null. */
export function parseBps(text: string): number | null {
  const clean = text.trim().replace("%", "").replace(",", ".").trim();
  if (!/^\d{1,3}(\.\d{1,2})?$/.test(clean)) return null;
  const bps = Math.round(Number(clean) * 100);
  return bps > 0 && bps <= 10000 ? bps : null;
}

const usesAmount = (kind: PayRuleKind) => kind !== "percent_of_sales";

/** The rule form's errors, under their fields (message keys of `CoachPay`). */
export function ruleErrors(draft: RuleDraft): RuleErrors {
  const errors: RuleErrors = {};
  if (usesAmount(draft.kind)) {
    const cents = parseCents(draft.amount);
    if (cents === null || cents <= 0) errors.amount = "errorAmount";
  } else if (parseBps(draft.percent) === null) {
    errors.percent = "errorPercent";
  }
  if (draft.kind === "per_class" && draft.minAttendees.trim() !== "" && !/^\d{1,3}$/.test(draft.minAttendees.trim())) {
    errors.minAttendees = "errorWholeNumber";
  }
  if (draft.kind === "per_attendee" && draft.countStatuses.length === 0) errors.countStatuses = "errorCountStatuses";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(draft.startsOn)) errors.startsOn = "errorDate";
  if (draft.endsOn && draft.endsOn < draft.startsOn) errors.endsOn = "errorEndsBeforeStart";
  return errors;
}

/** The body for `POST /rules` (or `PATCH /rules/:id` without the person). */
export function ruleBody(draft: RuleDraft, userId: string): PayRuleBody {
  const body: PayRuleBody = {
    coach_user_id: userId,
    kind: draft.kind,
    starts_on: draft.startsOn,
    ends_on: draft.endsOn || null,
    amount_basis: draft.basis,
    note: draft.note.trim() || null,
  };
  if (usesAmount(draft.kind)) body.amount_cents = parseCents(draft.amount);
  else {
    body.percent_bps = parseBps(draft.percent);
    body.sales_scope = draft.salesScope;
  }
  if (draft.kind === "per_class") body.min_attendees = draft.minAttendees.trim() === "" ? 0 : Number(draft.minAttendees);
  if (draft.kind === "per_attendee") body.count_statuses = COUNT_STATUSES.filter((status) => draft.countStatuses.includes(status));
  if (draft.kind === "fixed") body.frequency = draft.frequency;
  return body;
}

// ── Periods ─────────────────────────────────────────────────────────────────

/** Mockup s5 A: one primary action per status (Έγκριση, then Εξαγωγή CSV); an exported period is locked. */
/**
 * The period's one filled button. Approving needs manage_billing; the CSV of
 * an approved period is also for whoever only reads the finance reports (the
 * accountant), as the API allows.
 */
export function primaryAction(status: PayPeriodStatus, canEdit = true): "approve" | "export" | null {
  if (status === "draft") return canEdit ? "approve" : null;
  if (status === "approved") return "export";
  return null;
}

/** «Οκτώβριος 2026» for a whole calendar month, otherwise «1–15 Οκτ 2026» (gym-local dates). */
export function periodLabel(startsOn: string, endsOn: string, locale: string): string {
  const start = new Date(`${startsOn}T12:00:00Z`);
  const end = new Date(`${endsOn}T12:00:00Z`);
  const lastOfMonth = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0, 12));
  if (start.getUTCDate() === 1 && end.getTime() === lastOfMonth.getTime()) {
    const text = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(start);
    return text.charAt(0).toLocaleUpperCase(locale) + text.slice(1);
  }
  try {
    return new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).formatRange(start, end);
  } catch {
    return `${startsOn} – ${endsOn}`;
  }
}

const iso = (date: Date) => date.toISOString().slice(0, 10);

/**
 * The dates a new period suggests: the month after the latest period, or
 * the last whole calendar month before `today` when there is none.
 */
export function nextPeriodRange(periods: Pick<PayPeriodSummary, "ends_on">[], today: string): { startsOn: string; endsOn: string } {
  const latest = periods.map((period) => period.ends_on).sort().at(-1);
  let start: Date;
  if (latest) {
    const day = new Date(`${latest}T12:00:00Z`);
    start = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate() + 1, 12));
  } else {
    const now = new Date(`${today}T12:00:00Z`);
    start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1, 12));
  }
  const end = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0, 12));
  return { startsOn: iso(start), endsOn: iso(end) };
}

/** Periods are at most 92 days (ADR-341); the end is on or after the start. */
export function periodRangeError(startsOn: string, endsOn: string): "errorDate" | "errorEndsBeforeStart" | "errorPeriodTooLong" | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startsOn) || !/^\d{4}-\d{2}-\d{2}$/.test(endsOn)) return "errorDate";
  if (endsOn < startsOn) return "errorEndsBeforeStart";
  const days = (Date.parse(`${endsOn}T00:00:00Z`) - Date.parse(`${startsOn}T00:00:00Z`)) / 86_400_000 + 1;
  return days > 92 ? "errorPeriodTooLong" : null;
}

/** «Μικτά X · Καθαρά Y»: both subtotals, never one unlabelled sum (ADR-382). */
export function grossNet(record: { gross_cents: number; net_cents: number }) {
  return { gross: record.gross_cents, net: record.net_cents };
}

/** Lines added by hand survive recalculation and are the only ones that can be removed. */
export function isManual(line: Pick<PayLine, "source_type">): boolean {
  return line.source_type === "manual";
}

/** A net line is marked (ADR-382: `deviates_from_default`). */
export function isNet(line: Pick<PayLine, "amount_basis">): boolean {
  return line.amount_basis === "net";
}

/** «32 τμήματα × 15,00 €»: how a group of lines was paid (quantity × rate, or a percent of a base). */
export function groupSentence(group: PayGroup, money: Money, percent: (bps: number) => string): Sentence {
  const terms = (group.terms ?? {}) as Record<string, unknown>;
  const quantity = group.quantity_divisor ? group.quantity / group.quantity_divisor : group.quantity;
  if (group.kind === "percent_of_sales" && typeof terms.percent_bps === "number") {
    return { key: "groupPercent", values: { percent: percent(terms.percent_bps), base: money(group.base_cents ?? 0) } };
  }
  if (typeof group.unit_cents === "number" && group.unit_cents !== 0 && ["per_class", "per_attendee", "per_session", "overtime", "allowance", "fixed"].includes(group.kind)) {
    return { key: `group_${group.kind}`, values: { count: Math.round(quantity * 100) / 100, unit: money(group.unit_cents) } };
  }
  return { key: `kind_${group.kind}`, values: {} };
}

// ── Lines added by hand ─────────────────────────────────────────────────────

export const ADJUSTMENT_KINDS: AdjustmentKind[] = ["adjustment", "ad_hoc", "non_taxable_reimbursement"];

/** ANR 2026-11-02: «Μη φορολογητέο» defaults to net; everything else to gross. */
export function defaultBasis(kind: AdjustmentKind): AmountBasis {
  return kind === "non_taxable_reimbursement" ? "net" : "gross";
}

/**
 * A line added by hand: an adjustment kind, an allowance from the catalogue,
 * or one-off overtime (hours × a rate per hour, from an overtime item;
 * ANR 2026-11-04). `hours` and `rate` are overtime only; an empty `rate`
 * means the item's own.
 */
export type LineDraft = {
  kind: AdjustmentKind | "allowance" | "overtime";
  amount: string;
  note: string;
  basis: AmountBasis;
  itemId: string;
  quantity: string;
  hours: string;
  rate: string;
};
export type LineField = "amount" | "note" | "itemId" | "quantity" | "hours" | "rate";

export function emptyLineDraft(): LineDraft {
  return { kind: "adjustment", amount: "", note: "", basis: "gross", itemId: "", quantity: "1", hours: "", rate: "" };
}

/** At most a week of overtime on one line, as the API allows. */
const MAX_OVERTIME_MINUTES = 7 * 24 * 60;

/** «2», «2,5» or «2:30» hours → minutes; anything else, zero or over a week → null. */
export function parseHours(text: string): number | null {
  const clean = text.trim().replace(",", ".");
  let minutes: number;
  const clock = /^(\d{1,3}):([0-5]\d)$/.exec(clean);
  if (clock) minutes = Number(clock[1]) * 60 + Number(clock[2]);
  else if (/^\d{1,3}(\.\d{1,2})?$/.test(clean)) minutes = Math.round(Number(clean) * 60);
  else return null;
  return minutes > 0 && minutes <= MAX_OVERTIME_MINUTES ? minutes : null;
}

/** The rate one-off overtime is paid at: the typed one, or the item's. */
export function overtimeRate(draft: LineDraft, item: PayItem | null): number | null {
  if (draft.rate.trim() === "") return item?.amount_cents ?? null;
  const cents = parseCents(draft.rate);
  return cents !== null && cents > 0 ? cents : null;
}

/** One-off overtime's total in cents (rounded down, like the API), or null while a field is not valid. */
export function overtimeTotal(draft: LineDraft, item: PayItem | null): number | null {
  const minutes = parseHours(draft.hours);
  const rate = overtimeRate(draft, item);
  return minutes === null || rate === null ? null : Math.floor((rate * minutes) / 60);
}

/** A correction may be negative; an ad hoc payment and «Μη φορολογητέο» are positive. Every kind needs a note, except an allowance. */
export function lineErrors(draft: LineDraft, item: PayItem | null): Partial<Record<LineField, string>> {
  const errors: Partial<Record<LineField, string>> = {};
  if (draft.kind === "allowance") {
    if (!item) errors.itemId = "errorItem";
    if (item?.unit === "per_occurrence" && !/^[1-9]\d{0,2}$/.test(draft.quantity.trim())) errors.quantity = "errorWholeNumber";
    return errors;
  }
  if (draft.kind === "overtime") {
    if (!item) errors.itemId = "errorOvertimeItem";
    if (parseHours(draft.hours) === null) errors.hours = "errorHours";
    if (draft.rate.trim() !== "" && overtimeRate(draft, item) === null) errors.rate = "errorAmount";
    if (draft.note.trim() === "") errors.note = "errorNoteRequired";
    return errors;
  }
  const cents = parseCents(draft.amount, true);
  if (cents === null || cents === 0) errors.amount = "errorAmount";
  else if (draft.kind !== "adjustment" && cents < 0) errors.amount = "errorPositive";
  if (draft.note.trim() === "") errors.note = "errorNoteRequired";
  return errors;
}

/** One-off overtime for `POST …/pay-items`; the rate goes only when it differs from the item's. */
export function overtimeLineBody(draft: LineDraft, userId: string, item: PayItem): PayItemLineBody {
  const rate = overtimeRate(draft, item);
  return {
    user_id: userId,
    pay_item_id: item.id,
    minutes: parseHours(draft.hours) ?? 0,
    ...(rate !== null && rate !== item.amount_cents ? { unit_cents: rate } : {}),
    note: draft.note.trim(),
    amount_basis: draft.basis,
  };
}

export function adjustmentBody(draft: LineDraft, userId: string): AdjustmentBody {
  return {
    coach_user_id: userId,
    kind: draft.kind as AdjustmentKind,
    amount_cents: parseCents(draft.amount, draft.kind === "adjustment") ?? 0,
    note: draft.note.trim(),
    amount_basis: draft.basis,
  };
}

// ── Overtime and allowances ─────────────────────────────────────────────────

export type ItemDraft = {
  kind: PayItem["kind"];
  name: string;
  amount: string;
  unit: PayItem["unit"];
  threshold: string;
  roles: PayRole[];
  basis: AmountBasis;
};
export type ItemField = "name" | "amount" | "threshold" | "roles";

export function emptyItemDraft(kind: PayItem["kind"] = "allowance"): ItemDraft {
  return { kind, name: "", amount: "", unit: kind === "overtime" ? "per_hour" : "per_period", threshold: "", roles: ["coach"], basis: "gross" };
}

export function itemDraftFrom(item: PayItem): ItemDraft {
  return {
    kind: item.kind,
    name: item.name,
    amount: (item.amount_cents / 100).toFixed(2),
    unit: item.unit,
    threshold: item.weekly_threshold == null ? "" : String(item.weekly_threshold),
    roles: [...item.roles],
    basis: item.amount_basis,
  };
}

export function itemErrors(draft: ItemDraft): Partial<Record<ItemField, string>> {
  const errors: Partial<Record<ItemField, string>> = {};
  if (draft.name.trim() === "" || draft.name.trim().length > 120) errors.name = "errorName";
  const cents = parseCents(draft.amount);
  if (cents === null || cents <= 0) errors.amount = "errorAmount";
  if (draft.kind === "overtime") {
    const hours = draft.threshold.trim();
    if (!/^\d{1,3}$/.test(hours) || Number(hours) > 168) errors.threshold = "errorThreshold";
  }
  if (draft.roles.length === 0) errors.roles = "errorRoles";
  return errors;
}

export function itemBody(draft: ItemDraft): PayItemBody {
  return {
    kind: draft.kind,
    name: draft.name.trim(),
    amount_cents: parseCents(draft.amount) ?? 0,
    unit: draft.kind === "overtime" ? "per_hour" : draft.unit,
    weekly_threshold: draft.kind === "overtime" ? Number(draft.threshold) : null,
    roles: PAY_ROLES.filter((role) => draft.roles.includes(role)),
    amount_basis: draft.basis,
  };
}

/** The allowances a person can be given: active ones (overtime is calculated, never added by hand). */
export function addableItems(items: PayItem[]): PayItem[] {
  return items.filter((item) => item.kind === "allowance" && !item.archived_at);
}

/** The overtime items one-off overtime can be paid by (their rate is the default). */
export function overtimeItems(items: PayItem[]): PayItem[] {
  return items.filter((item) => item.kind === "overtime" && !item.archived_at);
}

// ── Files and dates ─────────────────────────────────────────────────────────

/** A downloaded file's name: `coach-pay-2026-10-01-2026-10-31.csv`, `pay-statement-….pdf`. */
export function payFileName(prefix: "coach-pay" | "pay-statement", period: { starts_on: string; ends_on: string }, extension: "csv" | "pdf"): string {
  return [prefix, period.starts_on, period.ends_on].join("-") + "." + extension;
}

/** A calendar date (YYYY-MM-DD) at noon UTC, so formatting it never shifts the day. */
export function calendarNoon(iso: string): Date {
  return new Date(iso.slice(0, 10) + "T12:00:00Z");
}

/**
 * The group a line belongs to, as the API builds `groups` (ADR-382
 * `StatementGroups`): its rule, or its pay item and kind, or its kind when
 * added by hand, and its gross/net basis. Clawbacks join their rule's group.
 */
export function groupKeyOf(line: Pick<PayLine, "rule_id" | "pay_item_id" | "kind" | "amount_basis">): string {
  const basis = line.amount_basis || "gross";
  if (line.rule_id) return ["rule", line.rule_id, basis].join(":");
  if (line.pay_item_id) return ["pay_item", line.pay_item_id, line.kind, basis].join(":");
  return ["manual", line.kind, basis].join(":");
}

/** The PDF writer's languages (ADR-382); right-to-left ones fall back to English. */
export function payslipLanguage(locale: string): string {
  const supported = ["el", "en", "de", "fr", "it", "nl", "es", "pt-PT", "ru", "bg"];
  if (supported.includes(locale)) return locale;
  const short = locale.split("-")[0]!;
  return supported.includes(short) ? short : "en";
}

/** A copy of `record` without `key` (an update body never carries the person or kind it was created with). */
export function withoutKey<T extends object, K extends keyof T>(record: T, key: K): Omit<T, K> {
  const copy = { ...record };
  delete copy[key];
  return copy;
}
