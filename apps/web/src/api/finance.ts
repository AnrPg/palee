import { apiRequest } from "@/api/client";
import type { PackageCatalog } from "@/components/admin/finance/packages/package-catalog";
import type { ValueOverride } from "@/components/admin/finance/shared/member-standing";
import type { Standing } from "@/components/finance/standing";
import type { LocationScopePayload } from "@/lib/location-scope";

export type FinanceRecord = Record<string, unknown>;

/** ADR-797: one active invoice, receipt or payment in «Εκκαθάριση συναλλαγών». */
export type FinanceCleanupRecordType = "invoice" | "receipt" | "payment";

export type FinanceCleanupRecord = {
  id: string;
  record_type: FinanceCleanupRecordType;
  /** The document number (a payment: its invoice's or receipt's), if any. */
  code?: string | null;
  membership_id?: string | null;
  user_id?: string | null;
  finance_invoice_id?: string | null;
  amount_cents?: number | null;
  currency?: string | null;
  status?: string | null;
  issued_on?: string | null;
  due_on?: string | null;
  paid_on?: string | null;
  /** The issue date of a document, the paid date of a payment. */
  occurred_on?: string | null;
  payment_method?: string | null;
  package_id?: string | null;
  package_name?: string | null;
  customer_name?: string | null;
  customer_handle?: string | null;
  customer_email?: string | null;
  inserted_at?: string | null;
  deleted_at?: string | null;
};

export type FinanceCleanupLinkedRecord = {
  id: string;
  record_type: FinanceCleanupRecordType;
  code?: string | null;
  amount_cents?: number | null;
  currency?: string | null;
  status?: string | null;
  payment_method?: string | null;
  occurred_on?: string | null;
};

export type FinanceCleanupRecordDetails = FinanceCleanupRecord & {
  invoice_type?: string | null;
  service_period_start?: string | null;
  service_period_end?: string | null;
  subtotal_cents?: number | null;
  discount_cents?: number | null;
  balance_due_cents?: number | null;
  reversed_cents?: number | null;
  notes?: string | null;
  fiscal_receipt_ref?: string | null;
  revenue_stream?: string | null;
  created_by_id?: string | null;
  created_by_name?: string | null;
  lines: Array<{
    id: string;
    description?: string | null;
    quantity?: number | null;
    unit_amount_cents?: number | null;
    discount_cents?: number | null;
    total_cents?: number | null;
  }>;
  linked: FinanceCleanupLinkedRecord[];
};

/** ADR-797: the filters of «Εκκαθάριση συναλλαγών» as API query params. */
export type FinanceCleanupQuery = {
  q?: string;
  user_id?: string;
  package_id?: string;
  from?: string;
  to?: string;
  kind?: FinanceCleanupRecordType;
  cursor?: string;
  limit?: string;
};

export async function fetchFinanceCleanupRecords(token: string, params: FinanceCleanupQuery = {}) {
  const entries = Object.entries(params).filter((entry): entry is [string, string] => Boolean(entry[1]));
  const query = new URLSearchParams(entries).toString();
  return apiRequest<{ records: FinanceCleanupRecord[]; next_cursor?: string | null }>(
    `/admin/finance/cleanup-records${query ? `?${query}` : ""}`,
    { token },
  );
}

export async function fetchFinanceCleanupRecord(token: string, recordType: FinanceCleanupRecordType, recordId: string) {
  const query = new URLSearchParams({ record_type: recordType }).toString();
  return apiRequest<{ record: FinanceCleanupRecordDetails }>(
    `/admin/finance/cleanup-records/${encodeURIComponent(recordId)}?${query}`,
    { token },
  );
}

/** Every package, inactive ones too: older records may belong to them. */
export async function fetchFinanceCleanupPackages(token: string) {
  return apiRequest<{ packages: Array<{ id: string; name: string; active: boolean }> }>(
    "/admin/finance/cleanup-records/packages",
    { token },
  );
}

export async function purgeFinanceRecord(
  token: string,
  recordId: string,
  body: { record_type: string; password: string; reason?: string },
) {
  return apiRequest<{ record: FinanceCleanupRecord; purged_linked_records?: Record<string, number> }>(
    `/admin/finance/cleanup-records/${recordId}/purge`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

/** ADR-186 §7: `locationIds` (comma-separated) narrows the summary to some branches. */
export async function fetchFinanceSummary(token: string, locationIds?: string) {
  const query = locationIds ? `?${new URLSearchParams({ location_ids: locationIds }).toString()}` : "";
  return apiRequest<FinanceRecord>(`/admin/finance/summary${query}`, { token });
}

/** ADR-462: the finance summary for a «Στατιστικά» period and filters (`analyticsApiQuery`). */
export async function fetchFinanceAnalyticsSummary(token: string, query: Record<string, string>) {
  return apiRequest<FinanceRecord>(`/admin/finance/summary?${new URLSearchParams(query).toString()}`, { token });
}

/** ADR-186 §7: the `location_ids` query of a list on a branch-filtered page, or "". */
function branchQuery(locationIds?: string) {
  return locationIds ? `?${new URLSearchParams({ location_ids: locationIds }).toString()}` : "";
}

/** `locationIds` (the page branch filter) keeps the packages valid at one of them or everywhere. */
export async function fetchFinancePackages(token: string, locationIds?: string) {
  return apiRequest<{ packages: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/packages${branchQuery(locationIds)}`,
    { token },
  );
}

export async function fetchPackageCatalog(token: string) {
  return apiRequest<PackageCatalog>("/admin/finance/package-catalog", { token });
}

export async function fetchFinancePackage(token: string, packageId: string) {
  return apiRequest<{ package: FinanceRecord }>(`/admin/finance/packages/${packageId}`, { token });
}

export async function createFinancePackage(token: string, body: FinanceRecord) {
  return apiRequest<{ package: FinanceRecord }>("/admin/finance/packages", {
    method: "POST",
    token,
    body,
  });
}

export async function updateFinancePackage(token: string, packageId: string, body: FinanceRecord) {
  return apiRequest<{ package: FinanceRecord }>(`/admin/finance/packages/${packageId}`, {
    method: "PATCH",
    token,
    body,
  });
}

/** ADR-770: when a changed term reaches a holder. */
export type TermTiming = "now" | "next_period" | "never" | "purchase_only";

export type TermChange = { key: string; from: unknown; to: unknown; timing: TermTiming; direction?: "better" | "worse" | "neutral" };

export type TermsHolder = {
  subscription_id: string;
  membership_id: string;
  user_id: string;
  nickname: string | null;
  next_period_on: string | null;
  now_count: number;
  next_count: number;
  notes: Array<"custom_price" | "renewal_stopped" | "ends_before">;
};

export type PackageTermsPreview = {
  holders_count: number;
  needs_choice: boolean;
  changes: TermChange[];
  earliest_next_on: string | null;
  holders: TermsHolder[];
};

export type TermsChoice = { apply_to: "active" | "new_only"; excluded_subscription_ids: string[] };

/** One package change as it reached a subscription (pending until `effective_on`). */
export type SubscriptionTermUpdate = {
  id: string;
  timing: "now" | "next_period";
  status: "pending" | "applied";
  effective_on: string;
  applied_at: string | null;
  inserted_at: string;
  changes: TermChange[];
};

/** ADR-770: what saving `body` would do to the package's holders (nothing is saved). */
export async function previewFinancePackageTerms(token: string, packageId: string, body: FinanceRecord) {
  return apiRequest<{ preview: PackageTermsPreview }>(`/admin/finance/packages/${packageId}/terms-preview`, {
    method: "POST",
    token,
    body,
  });
}

export async function retireFinancePackage(
  token: string,
  packageId: string,
  replacementPackageByRole: Record<string, string>,
) {
  return apiRequest<{ package: FinanceRecord; reassigned_count: number; affected_by_role: Record<string, number> }>(
    `/admin/finance/packages/${packageId}/retire`,
    {
      method: "PATCH",
      token,
      body: { replacement_package_by_role: replacementPackageByRole },
    },
  );
}

export type EntitlementBackfillReport = {
  dry_run: boolean;
  ready: boolean;
  counts: Record<string, number>;
  failures: Array<{ user_id: string; reason: string }>;
};

export async function backfillFinanceEntitlements(token: string, body: { dry_run: boolean; package_by_role: { member?: string; athlete?: string } }) {
  return apiRequest<EntitlementBackfillReport>("/admin/finance/entitlements/backfill", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchFinanceMembers(token: string, params: Record<string, string> = {}) {
  const qs = new URLSearchParams(params).toString();
  return apiRequest<{ members: FinanceRecord[]; meta: FinanceRecord; branch_filter?: LocationScopePayload }>(
    `/admin/finance/members${qs ? `?${qs}` : ""}`,
    { token },
  );
}

export async function fetchFinanceMember(token: string, userId: string) {
  return apiRequest<{
    membership: FinanceRecord | null;
    package_subscriptions: FinanceRecord[];
    invoices: FinanceRecord[];
    payments: FinanceRecord[];
    payment_reversals: FinanceRecord[];
    promotion_redemptions: FinanceRecord[];
    credit_ledger_entries: FinanceRecord[];
    credit_balance: number;
    entitlement?: FinanceRecord;
    /** The one standing every screen shows (ledger, profile, the member's own pages). */
    standing?: Standing | null;
  }>(`/admin/finance/members/${userId}`, { token });
}

export async function updateFinanceMember(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ membership: FinanceRecord }>(`/admin/finance/members/${userId}`, {
    method: "PATCH",
    token,
    body,
  });
}

/**
 * ADR-274: staff set a value Palee works out by hand: the member's `status`,
 * or a subscription's last day (`ends_on`, with `subscription_id`).
 */
export async function setFinanceOverride(
  token: string,
  userId: string,
  field: "status" | "ends_on",
  body: { value: string; reason?: string; reason_shared?: boolean; subscription_id?: string; commitment_override_reason?: string },
) {
  return apiRequest<{ override: ValueOverride }>(`/admin/finance/members/${userId}/overrides/${field}`, {
    method: "PUT",
    token,
    body,
  });
}

/** ADR-274: puts a value set by hand back to automatic. */
export async function resetFinanceOverride(
  token: string,
  userId: string,
  field: "status" | "ends_on",
  subscriptionId?: string,
) {
  const query = subscriptionId ? `?subscription_id=${encodeURIComponent(subscriptionId)}` : "";
  return apiRequest<{ override: ValueOverride }>(`/admin/finance/members/${userId}/overrides/${field}${query}`, {
    method: "DELETE",
    token,
  });
}

/** ADR-220: staff turn a member's subscription renewal on or off. */
export async function setFinanceMemberAutoRenew(token: string, userId: string, subscriptionId: string, autoRenew: boolean) {
  return apiRequest<{ package_subscription: FinanceRecord }>(
    `/admin/finance/members/${userId}/subscriptions/${encodeURIComponent(subscriptionId)}/auto-renew`,
    { method: "PUT", token, body: { auto_renew: autoRenew } },
  );
}

/** ADR-220: staff mark a member as leaving the box (no day: when what they paid for ends). */
export async function markFinanceMemberLeft(
  token: string,
  userId: string,
  body: { reason?: string | null; reason_shared?: boolean },
) {
  return apiRequest<{ membership: FinanceRecord; leaving_on: string; voided_invoice_count: number; outstanding_cents: number }>(
    `/admin/finance/members/${userId}/leave`,
    { method: "POST", token, body },
  );
}

/** ADR-220: staff undo a member's leave. */
export async function undoFinanceMemberLeft(token: string, userId: string) {
  return apiRequest<{ membership: FinanceRecord }>(`/admin/finance/members/${userId}/leave`, { method: "DELETE", token });
}

/** ADR-660: what removing a member's package would touch. */
export type PackageRemovalPreview = {
  package_name: string;
  untouched_invoices: { id: string; total_cents: number; currency?: string | null; due_date?: string | null }[];
  kept_owed_cents: number;
  paid_cents: number;
  currency?: string | null;
  upcoming_bookings: number;
  /** Whether this staff member may cancel the unpaid invoice (manage billing). */
  may_write_off: boolean;
  undo_seconds: number;
};

export type PackageRemoval = {
  id: string;
  subscription_id: string;
  package_name: string;
  removed_on: string;
  invoice_choice: "void" | "keep" | null;
  voided_invoice_count: number;
  undo_until: string;
  undone_at?: string | null;
  /** «Αλλαγή πακέτου»: the package that took this one's place today. */
  replacement_subscription_id?: string | null;
  replacement_package_name?: string | null;
};

export async function fetchPackageRemovalPreview(token: string, userId: string, subscriptionId: string) {
  return apiRequest<{ removal: PackageRemovalPreview }>(
    `/admin/finance/members/${userId}/subscriptions/${encodeURIComponent(subscriptionId)}/removal`,
    { token },
  );
}

/**
 * ADR-660: removes the package from today, or changes it for
 * `replacement_package_id` in the same step; it can be undone until `undo_until`.
 */
export async function removeFinancePackage(
  token: string,
  userId: string,
  subscriptionId: string,
  body: { invoice_choice?: "void" | "keep"; reason?: string; reason_shared?: boolean; replacement_package_id?: string },
) {
  return apiRequest<{ removal: PackageRemoval }>(
    `/admin/finance/members/${userId}/subscriptions/${encodeURIComponent(subscriptionId)}/removal`,
    { method: "POST", token, body },
  );
}

/** ADR-660: «Αναίρεση» while the removal's minute is open. */
export async function undoPackageRemoval(token: string, userId: string, removalId: string) {
  return apiRequest<{ removal: PackageRemoval }>(
    `/admin/finance/members/${userId}/package-removals/${encodeURIComponent(removalId)}`,
    { method: "DELETE", token },
  );
}

export async function assignFinancePackage(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ package_subscription: FinanceRecord }>(`/admin/finance/members/${userId}/packages`, {
    method: "POST",
    token,
    body,
  });
}

export async function recordFinancePayment(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ payment: FinanceRecord }>(`/admin/finance/members/${userId}/payments`, {
    method: "POST",
    token,
    body,
  });
}

export type FinanceReceipt = {
  document_type: "receipt";
  reference: string;
  issued_on: string;
  amount_cents: number;
  currency: string;
  description: string;
  membership_package_subscription_id?: string | null;
  package_name?: string | null;
  package_code_snapshot?: string | null;
  package_family_snapshot?: string | null;
  invoice: FinanceRecord;
  payment: FinanceRecord;
};

export async function createFinanceReceipt(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ receipt: FinanceReceipt }>(`/admin/finance/members/${userId}/receipts`, {
    method: "POST",
    token,
    body,
  });
}

/**
 * ADR-222: money received at the desk and the document it left: the open
 * invoice it went against, a paid receipt or a paid invoice, as the box's
 * billing setup says. `replayed` is true when the same idempotency key was
 * already recorded, and the first answer comes back unchanged.
 */
export type ReceivedPayment = Omit<FinanceReceipt, "document_type"> & {
  document_type: "receipt" | "invoice";
  replayed: boolean;
};

export async function receiveFinancePayment(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ received: ReceivedPayment }>(`/admin/finance/members/${userId}/payments/receive`, {
    method: "POST",
    token,
    body,
  });
}

export async function createFinanceInvoice(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/members/${userId}/invoices`, {
    method: "POST",
    token,
    body,
  });
}

export async function generateRenewalInvoice(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/members/${userId}/invoices/renewal`, {
    method: "POST",
    token,
    body,
  });
}

export async function getInvoiceUploadUrl(
  token: string,
  invoiceId: string,
  fileName: string,
  contentType: string,
) {
  return apiRequest<{ upload_url: string; file_key: string; content_type: string }>(
    `/admin/finance/invoices/${invoiceId}/upload-url`,
    { method: "POST", token, body: { file_name: fileName, content_type: contentType } },
  );
}

export async function getInvoiceDownloadUrl(token: string, invoiceId: string) {
  return apiRequest<{ download_url: string; file_name: string }>(
    `/admin/finance/invoices/${invoiceId}/download-url`,
    { token },
  );
}

export async function updateFinanceInvoice(
  token: string,
  invoiceId: string,
  body: { due_date?: string; notes?: string },
) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function issueFinanceInvoice(token: string, invoiceId: string, body: FinanceRecord = {}) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}/issue`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function voidFinanceInvoice(token: string, invoiceId: string, body: FinanceRecord = {}) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}/void`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function createManualCredit(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(`/admin/finance/members/${userId}/credits`, {
    method: "POST",
    token,
    body,
  });
}

export async function applyCreditToPayment(token: string, userId: string, paymentId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/payments/${paymentId}/credits`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function applyCreditToInvoice(token: string, userId: string, invoiceId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/invoices/${invoiceId}/credits`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function reverseFinancePayment(token: string, userId: string, paymentId: string, body: FinanceRecord) {
  return apiRequest<{ payment_reversal: FinanceRecord }>(
    `/admin/finance/members/${userId}/payments/${paymentId}/reversals`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function reverseCreditLedgerEntry(token: string, userId: string, entryId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/credits/${entryId}/reversals`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function fetchFinanceQueues(token: string, params: Record<string, string> = {}) {
  const query = new URLSearchParams(params).toString();
  return apiRequest<{ queues: Record<string, FinanceRecord[]> }>(
    `/admin/finance/queues${query ? `?${query}` : ""}`,
    { token },
  );
}

/** `locationIds` (the page branch filter) keeps the promotions valid at one of them or everywhere. */
export async function fetchPromotionCampaigns(token: string, locationIds?: string) {
  return apiRequest<{ promotion_campaigns: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/promotions${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createPromotionCampaign(token: string, body: FinanceRecord) {
  return apiRequest<{ promotion_campaign: FinanceRecord }>("/admin/finance/promotions", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchPromotionCodes(token: string, campaignId: string) {
  return apiRequest<{ promotion_codes: FinanceRecord[] }>(`/admin/finance/promotions/${campaignId}/codes`, {
    token,
  });
}

export async function createPromotionCode(token: string, campaignId: string, body: FinanceRecord) {
  return apiRequest<{ promotion_code: FinanceRecord }>(`/admin/finance/promotions/${campaignId}/codes`, {
    method: "POST",
    token,
    body,
  });
}

export async function redeemPromotion(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ promotion_redemption: FinanceRecord }>(
    `/admin/finance/members/${userId}/promotion-redemptions`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

/** `locationIds` (the page branch filter) keeps the referrals of people at home there. */
export async function fetchReferralEvents(token: string, locationIds?: string) {
  return apiRequest<{ referral_events: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/referrals${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createReferralEvent(token: string, body: FinanceRecord) {
  return apiRequest<{ referral_event: FinanceRecord }>("/admin/finance/referrals", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchReferralPrograms(token: string) {
  return apiRequest<{ referral_programs: FinanceRecord[] }>("/admin/finance/referral-programs", { token });
}

export async function createReferralProgram(token: string, body: FinanceRecord) {
  return apiRequest<{ referral_program: FinanceRecord }>("/admin/finance/referral-programs", {
    method: "POST",
    token,
    body,
  });
}

export async function updateReferralProgram(token: string, referralProgramId: string, body: FinanceRecord) {
  return apiRequest<{ referral_program: FinanceRecord }>(
    `/admin/finance/referral-programs/${referralProgramId}`,
    {
      method: "PATCH",
      token,
      body,
    },
  );
}

export async function updateReferralEventStatus(token: string, referralEventId: string, status: string) {
  return apiRequest<{ referral_event: FinanceRecord }>(`/admin/finance/referrals/${referralEventId}/status`, {
    method: "PATCH",
    token,
    body: { status },
  });
}

/** `locationIds` (the page branch filter) keeps the rewards of recipients at home there. */
export async function fetchReferralRewards(token: string, locationIds?: string) {
  return apiRequest<{ referral_rewards: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/referral-rewards${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createReferralReward(token: string, referralEventId: string, body: FinanceRecord) {
  return apiRequest<{ referral_reward: FinanceRecord }>(
    `/admin/finance/referrals/${referralEventId}/rewards`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function updateReferralRewardStatus(token: string, referralRewardId: string, status: string) {
  return apiRequest<{ referral_reward: FinanceRecord }>(
    `/admin/finance/referral-rewards/${referralRewardId}/status`,
    {
      method: "PATCH",
      token,
      body: { status },
    },
  );
}

export async function fetchAdminSearch(
  token: string,
  query = "",
  role = "all",
  filters: Record<string, string> = {},
) {
  const params = new URLSearchParams({ q: query, role, ...filters });
  return apiRequest<{ users: FinanceRecord[]; meta?: Record<string, unknown> }>(`/admin/search?${params.toString()}`, {
    token,
  });
}

// ── ADR-795: «Να μην εμφανιστεί ξανά σήμερα» on the money questions ─────────

export type MoneyConfirmationKind = "record_payment" | "desk_collect" | "shop_pickup" | "cash_refund";
export type ConfirmationSkips = { day: string; skipped: MoneyConfirmationKind[] };
export const CONFIRMATION_SKIPS_KEY = ["admin", "confirmation-skips"] as const;

/** The money questions this staff member chose not to see again today (the box's day). */
export function fetchConfirmationSkips(token: string) {
  return apiRequest<ConfirmationSkips>("/admin/confirmation-skips", { token });
}

/** Not again today, on every device of the account, until the box's midnight. */
export function skipConfirmationToday(token: string, kind: MoneyConfirmationKind) {
  return apiRequest<ConfirmationSkips>("/admin/confirmation-skips", { token, method: "POST", body: { kind } });
}
