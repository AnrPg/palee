import { chooseOption } from "./support/select";
import { expect, test, type Page, type Route } from "./support/test";

// Coach pay (ADR-341/382, W1 mockup): s4 A the rules per person in
// Οικονομικά › Αμοιβές coaches, s5 A a period with one primary button per
// status and statements that open into lines (net lines marked «Καθαρά»),
// and s6 A «Οι αμοιβές μου» for the coach. ADR-510 (ANR 2026-11-04): the
// catalogue's «Κάθε περίοδο · Μία φορά» forms, automatic allowances that can
// be taken off one person for one period, and the Ink sub-level dropdown. The API is stubbed; anything not
// stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { method: string; path: string; body: unknown };

function tokenFor(sub: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const user = (id: string, nickname: string, role: string) => ({
  id,
  nickname,
  role: "admin",
  email: `${id}@example.com`,
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role, settings: {} }],
});

const membership = (role: string, capabilities: Record<string, unknown>) => ({
  role,
  roles: [role],
  capabilities,
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
});

const ACCOUNTANT = user("acc-1", "Ελένη", "accountant");
const ACCOUNTANT_MEMBERSHIP = membership("accountant", { take_payments: "all", manage_billing: "all", view_finance_reports: true, view_billing_contacts: true });
const COACH = user("nikos", "Νίκος Α.", "coach");
const COACH_MEMBERSHIP = membership("coach", { run_classes: true, check_in: true });

const STAFF = [
  { user_id: "nikos", nickname: "Νίκος Α.", role: "coach" },
  { user_id: "anna", nickname: "Άννα Π.", role: "coach" },
];

const RULE = {
  id: "rule-1",
  coach_user_id: "nikos",
  coach_name: "Νίκος Α.",
  kind: "per_class",
  amount_cents: 1500,
  percent_bps: null,
  min_attendees: 0,
  count_statuses: [],
  sales_scope: null,
  frequency: null,
  starts_on: "2026-01-01",
  ends_on: null,
  amount_basis: "gross",
  currency: "EUR",
  archived_at: null,
  note: null,
};

const line = (over: Record<string, unknown>) => ({
  id: "line-x",
  kind: "per_class",
  amount_cents: 0,
  amount_basis: "gross",
  description: "",
  deviates_from_default: false,
  occurred_on: "2026-10-31",
  quantity: 1,
  rule_id: null,
  pay_item_id: null,
  source_type: "rule",
  source_id: null,
  note: null,
  ...over,
});

const STATEMENT = {
  id: "st-1",
  coach_user_id: "nikos",
  coach_name: "Νίκος Α.",
  gross_cents: 48000,
  net_cents: 3000,
  total_cents: 51000,
  line_count: 33,
  net_line_count: 1,
  groups: [
    { key: "rule:rule-1:gross", kind: "per_class", rule_id: "rule-1", pay_item_id: null, amount_basis: "gross", terms: null, line_count: 32, quantity: 32, unit_cents: 1500, amount_cents: 48000 },
    { key: "manual:non_taxable_reimbursement:net", kind: "non_taxable_reimbursement", rule_id: null, pay_item_id: null, amount_basis: "net", terms: null, line_count: 1, quantity: 1, amount_cents: 3000 },
  ],
  lines: [
    line({ id: "line-1", rule_id: "rule-1", amount_cents: 48000, quantity: 32, unit_cents: 1500 }),
    line({ id: "line-2", kind: "non_taxable_reimbursement", amount_basis: "net", amount_cents: 3000, source_type: "manual", note: "Εισιτήρια σεμιναρίου" }),
  ],
};

const period = (status: string, statements: unknown[] = [STATEMENT]) => ({
  id: "per-10",
  starts_on: "2026-10-01",
  ends_on: "2026-10-31",
  status,
  currency: "EUR",
  gross_cents: 48000,
  net_cents: 3000,
  calculated_at: "2026-11-01T08:00:00Z",
  reopen_reason: null,
  statements,
});

const OVERTIME_ITEM = {
  id: "item-ot",
  kind: "overtime",
  name: "Υπερωρία τμημάτων",
  amount_cents: 1200,
  unit: "per_hour",
  roles: ["coach"],
  weekly_threshold: 30,
  currency: "EUR",
  amount_basis: "gross",
  archived_at: null,
};

const PEOPLE = [
  { user_id: "nikos", name: "Νίκος Α.", pay_roles: ["coach"] },
  { user_id: "anna", name: "Άννα Π.", pay_roles: ["coach"] },
];

const TRAVEL_ITEM = {
  id: "item-travel",
  kind: "allowance",
  name: "Μετακίνηση",
  amount_cents: 2000,
  unit: "per_period",
  frequency: "period",
  roles: ["coach"],
  weekly_threshold: null,
  currency: "EUR",
  amount_basis: "net",
  archived_at: null,
};

const SKIP = { id: "skip-1", user_id: "nikos", pay_item_id: "item-travel", name: "Μετακίνηση", created_by_id: "acc-1", inserted_at: "2026-11-01T08:00:00Z" };

/** The statement once the recurring allowance reached Νίκος by itself. */
const WITH_TRAVEL = {
  ...STATEMENT,
  net_cents: 5000,
  groups: [
    ...STATEMENT.groups,
    { key: "pay_item:item-travel:allowance:net", kind: "allowance", rule_id: null, pay_item_id: "item-travel", amount_basis: "net", terms: { frequency: "period" }, line_count: 1, quantity: 1, unit_cents: 2000, amount_cents: 2000 },
  ],
  lines: [...STATEMENT.lines, line({ id: "line-travel", kind: "allowance", pay_item_id: "item-travel", amount_basis: "net", amount_cents: 2000, unit_cents: 2000, source_type: "pay_item" })],
};

// The owner manages settings too, so the catalogue offers both workflows.
const OWNER_MEMBERSHIP = membership("owner", { ...ACCOUNTANT_MEMBERSHIP.capabilities, manage_settings: true });

async function stubAccountant(page: Page, writes: Write[], items: unknown[] = [], first: ReturnType<typeof period> = period("draft"), member = ACCOUNTANT_MEMBERSHIP) {
  let current = first;
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ method, path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(ACCOUNTANT.id), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, ACCOUNTANT);
    if (path === "/api/memberships") return json(route, [member]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/staff/members") return json(route, { staff: STAFF });
    if (path === "/api/admin/finance/queues") return json(route, { queues: {} });
    if (path === "/api/admin/finance/package-catalog") return json(route, { types: [], modules: [] });
    if (path.startsWith("/api/admin/finance/members")) return json(route, { members: [], meta: {} });
    if (path === "/api/admin/coach-pay/rules" && method === "POST") return json(route, { rule: { ...RULE, id: "rule-2", coach_user_id: "anna", ...(body as object) } }, 201);
    if (path === "/api/admin/coach-pay/rules") return json(route, { rules: [RULE] });
    if (path === "/api/admin/coach-pay/people") return json(route, { people: PEOPLE });
    if (path === "/api/admin/coach-pay/items" && method === "POST") return json(route, { item: { id: "item-new", currency: "EUR", archived_at: null, ...(body as object) } }, 201);
    if (path === "/api/admin/coach-pay/items") return json(route, { items });
    if (path === "/api/admin/coach-pay/periods/per-10/adjustments" && method === "POST") return json(route, { period: current });
    if (path.startsWith("/api/admin/coach-pay/periods/per-10/adjustments/") && method === "DELETE") {
      current = { ...current, statements: [{ ...STATEMENT, groups: STATEMENT.groups, lines: STATEMENT.lines }], item_skips: [SKIP] } as typeof current;
      return json(route, { period: current });
    }
    if (path === "/api/admin/coach-pay/periods/per-10/skips/skip-1" && method === "DELETE") {
      current = first;
      return json(route, { period: current });
    }
    if (path === "/api/admin/coach-pay/periods/per-10/pay-items") return json(route, { period: current });
    if (path === "/api/admin/coach-pay/periods") return json(route, { periods: [current] });
    if (path === "/api/admin/coach-pay/periods/per-10/approve") {
      current = period("approved");
      return json(route, { period: current });
    }
    if (path === "/api/admin/coach-pay/periods/per-10/export") {
      current = period("exported");
      return route.fulfill({ status: 200, contentType: "text/csv", body: "person,gross,net\n" });
    }
    if (path === "/api/admin/coach-pay/periods/per-10") return json(route, { period: current });
    return json(route, {});
  });
}

test("rules read as sentences and someone without a rule stands out", async ({ page }) => {
  const writes: Write[] = [];
  await stubAccountant(page, writes);
  await page.goto("/admin/finance?tab=pay");

  const rules = page.getByTestId("pay-rules");
  const nikos = rules.getByTestId("pay-person").filter({ hasText: "Νίκος Α." });
  await expect(nikos.getByTestId("pay-rule-line")).toContainText("15,00 € ανά τμήμα");
  const anna = rules.getByTestId("pay-person").filter({ hasText: "Άννα Π." });
  await expect(anna.getByTestId("pay-person-no-rule")).toHaveText("Χωρίς κανόνα: δεν θα πληρωθεί");

  await anna.getByTestId("pay-add-rule").click();
  const form = page.getByTestId("pay-rule-form");
  await form.getByTestId("pay-rule-kind-per_attendee").click();
  await page.getByTestId("pay-rule-save").click();
  await expect(form.getByLabel("Ποσό")).toHaveAttribute("aria-invalid", "true");
  await form.getByLabel("Ποσό").fill("3");
  await page.getByTestId("pay-rule-save").click();
  await expect.poll(() => writes.find((write) => write.path === "/api/admin/coach-pay/rules")?.body).toMatchObject({
    coach_user_id: "anna",
    kind: "per_attendee",
    amount_cents: 300,
    amount_basis: "gross",
  });
});

test("a period has one primary button per status and statements open into lines", async ({ page }) => {
  // Desktop layout: on a phone this picker is a combobox (SegmentPicker collapses).
  await page.setViewportSize({ width: 1280, height: 800 });
  const writes: Write[] = [];
  await stubAccountant(page, writes);
  await page.goto("/admin/finance?tab=pay");
  await page.getByTestId("coach-pay-tab").locator('[data-segment="periods"]').click();

  await page.getByTestId("pay-period-row").first().click();
  const detail = page.getByTestId("pay-period");
  await expect(detail.getByTestId("pay-period-status")).toHaveText("Πρόχειρη");
  await expect(detail.getByTestId("pay-period-total")).toContainText("Μικτά 480,00");
  await expect(detail.getByTestId("pay-period-total")).toContainText("Καθαρά 30,00");
  await expect(detail.getByTestId("pay-export")).toHaveCount(0);

  await detail.getByTestId("pay-statement-toggle").click();
  const lines = detail.getByTestId("pay-statement-lines");
  await expect(lines).toContainText("32 τμήματα × 15,00");
  const reimbursement = lines.getByTestId("pay-manual-line");
  await expect(reimbursement).toContainText("Μη φορολογητέο");
  await expect(reimbursement.getByTestId("net-mark")).toHaveText("Καθαρά");

  await detail.getByTestId("pay-approve").click();
  await expect(detail.getByTestId("pay-period-status")).toHaveText("Εγκρίθηκε");
  await expect(detail.getByTestId("pay-approve")).toHaveCount(0);
  await expect(detail.getByTestId("pay-export")).toHaveText("Εξαγωγή CSV");
  await expect(detail.getByTestId("pay-reopen")).toBeVisible();

  const download = page.waitForEvent("download");
  await detail.getByTestId("pay-export").click();
  expect((await download).suggestedFilename()).toBe("coach-pay-2026-10-01-2026-10-31.csv");
  expect(writes.map((write) => write.path)).toContain("/api/admin/coach-pay/periods/per-10/approve");
});

test("one-off overtime: hours × the overtime rate, with a reason", async ({ page }) => {
  // ANR 2026-11-04: overtime outside classes is added by hand to one person's period.
  await page.setViewportSize({ width: 1280, height: 800 });
  const writes: Write[] = [];
  await stubAccountant(page, writes, [OVERTIME_ITEM]);
  await page.goto("/admin/finance?tab=pay");
  await page.getByTestId("coach-pay-tab").locator('[data-segment="periods"]').click();
  await page.getByTestId("pay-period-row").first().click();
  const detail = page.getByTestId("pay-period");
  await detail.getByTestId("pay-statement-toggle").click();
  await detail.getByTestId("pay-add-line").click();

  const dialog = page.getByTestId("pay-line-dialog");
  await dialog.getByTestId("pay-line-kind").getByRole("radio", { name: "Υπερωρία" }).click();
  await expect(dialog.getByTestId("pay-line-rate")).toHaveAttribute("placeholder", "12.00");
  await page.getByTestId("pay-line-save").click();
  await expect(dialog.getByTestId("pay-line-hours")).toHaveAttribute("aria-invalid", "true");

  await dialog.getByTestId("pay-line-hours").fill("2:30");
  await expect(dialog.getByTestId("pay-line-total")).toContainText("30,00");
  await dialog.getByLabel("Αιτιολογία (υποχρεωτική)").fill("Αγώνας του box");
  await page.getByTestId("pay-line-save").click();
  await expect
    .poll(() => writes.find((write) => write.path === "/api/admin/coach-pay/periods/per-10/pay-items")?.body)
    .toEqual({ user_id: "nikos", pay_item_id: "item-ot", minutes: 150, note: "Αγώνας του box", amount_basis: "gross" });
});

test("the catalogue explains both workflows and a recurring allowance has its own frequency", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const writes: Write[] = [];
  await stubAccountant(page, writes, [OVERTIME_ITEM], period("draft"), OWNER_MEMBERSHIP);
  await page.goto("/admin/finance?tab=pay&pay_view=items");

  const info = page.getByTestId("pay-items-info");
  await expect(info).toContainText("Κάθε περίοδο");
  await expect(info).toContainText("Μία φορά");
  await expect(info).toContainText("Τι είναι η «περίοδος»;");
  await expect(page.getByTestId("pay-item").filter({ hasText: "Υπερωρία τμημάτων" })).toContainText("πάνω από 30 ώρες την εβδομάδα");

  await page.getByTestId("pay-add-item-allowance").click();
  const dialog = page.getByTestId("pay-item-dialog");
  await expect(dialog.getByTestId("pay-item-mode").locator('[data-mode="recurring"]')).toHaveAttribute("aria-checked", "true");
  await expect(dialog.getByTestId("pay-item-explain")).toContainText("Μπαίνει μόνο του σε κάθε υπολογισμό");
  await dialog.getByLabel("Όνομα").fill("Μετακίνηση");
  await dialog.getByLabel("Ποσό", { exact: true }).fill("80");
  await dialog.getByTestId("pay-item-frequency").getByRole("radio", { name: "Την εβδομάδα" }).click();
  await page.getByTestId("pay-item-save").click();
  await expect
    .poll(() => writes.find((write) => write.method === "POST" && write.path === "/api/admin/coach-pay/items")?.body)
    .toMatchObject({ kind: "allowance", name: "Μετακίνηση", amount_cents: 8000, unit: "per_period", frequency: "weekly", roles: ["coach"] });
});

test("one time from the catalogue: «Άλλο ποσό» pays one person without creating an allowance", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const writes: Write[] = [];
  await stubAccountant(page, writes, [OVERTIME_ITEM], period("draft"), OWNER_MEMBERSHIP);
  await page.goto("/admin/finance?tab=pay&pay_view=items");

  await page.getByTestId("pay-add-item-allowance").click();
  const dialog = page.getByTestId("pay-item-dialog");
  await dialog.getByTestId("pay-item-mode").locator('[data-mode="oneOff"]').click();
  await chooseOption(page, dialog.getByTestId("pay-oneoff-person"), "anna");
  await expect(dialog.getByTestId("pay-oneoff-period")).toHaveAttribute("data-value", "per-10");
  // Άννα has no saved per-time allowance, so the form starts on «Άλλο ποσό».
  await expect(dialog.getByTestId("pay-oneoff-item")).toHaveAttribute("data-value", "other");
  await dialog.getByTestId("pay-oneoff-amount").fill("25");
  await dialog.getByTestId("pay-oneoff-note").fill("Βοήθεια στο σεμινάριο");
  await page.getByTestId("pay-item-save").click();
  await expect
    .poll(() => writes.find((write) => write.path === "/api/admin/coach-pay/periods/per-10/adjustments")?.body)
    .toEqual({ coach_user_id: "anna", kind: "ad_hoc", amount_cents: 2500, note: "Βοήθεια στο σεμινάριο" });
  expect(writes.some((write) => write.method === "POST" && write.path === "/api/admin/coach-pay/items")).toBe(false);
  await expect(page.getByTestId("pay-item-added")).toContainText("Άννα Π.");
});

test("a recurring allowance is taken off one person for this period and put back", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const writes: Write[] = [];
  await stubAccountant(page, writes, [TRAVEL_ITEM], period("draft", [WITH_TRAVEL]));
  await page.goto("/admin/finance?tab=pay&pay_view=periods");
  await page.getByTestId("pay-period-row").first().click();
  const detail = page.getByTestId("pay-period");
  await detail.getByTestId("pay-statement-toggle").click();
  const lines = detail.getByTestId("pay-statement-lines");
  await expect(lines).toContainText("Επίδομα: 1 × 20,00");

  // Calculated groups come first and lines added by hand after them (ADR-510),
  // so the allowance's menu is found by its row, not by position.
  const allowance = lines.locator(":scope > div").filter({ hasText: "Επίδομα: 1 × 20,00" });
  await allowance.getByRole("button", { name: "Ενέργειες γραμμής" }).click();
  await page.getByRole("menuitem", { name: "Όχι σε αυτή την περίοδο" }).click();
  await expect(lines.getByTestId("pay-skipped-item")).toContainText("Μετακίνηση: όχι σε αυτή την περίοδο");
  expect(writes.map((write) => `${write.method} ${write.path}`)).toContain("DELETE /api/admin/coach-pay/periods/per-10/adjustments/line-travel");

  await lines.getByTestId("pay-restore-item").click();
  await expect(lines.getByTestId("pay-skipped-item")).toHaveCount(0);
  expect(writes.map((write) => `${write.method} ${write.path}`)).toContain("DELETE /api/admin/coach-pay/periods/per-10/skips/skip-1");
});

test("on a phone the nested switch is an Ink dropdown, unlike the tabs above it", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const writes: Write[] = [];
  await stubAccountant(page, writes);
  await page.goto("/admin/finance?tab=pay");
  const sub = page.getByTestId("coach-pay-tab").locator('[data-segment-dropdown="sub"]');
  await expect(sub).toBeVisible();
  await expect(sub).toHaveAttribute("style", /background: var\(--text\)/);
  await expect(page.locator('[data-segment-dropdown="page"]').first()).toHaveAttribute("style", /background: var\(--primary\)/);
});

test("the coach sees «Οι αμοιβές μου»: the last period with its lines, then earlier ones", async ({ page }) => {
  const approved = { id: "per-10", starts_on: "2026-10-01", ends_on: "2026-10-31", status: "approved", currency: "EUR" };
  const earlier = { id: "per-9", starts_on: "2026-09-01", ends_on: "2026-09-30", status: "exported", currency: "EUR" };
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(COACH.id), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, COACH);
    if (path === "/api/memberships") return json(route, [COACH_MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/coach-pay/mine") {
      return json(route, {
        statements: [
          { ...STATEMENT, period: approved },
          { ...STATEMENT, id: "st-0", gross_cents: 58500, net_cents: 0, total_cents: 58500, groups: [], lines: [], period: earlier },
        ],
        totals: [{ currency: "EUR", gross_cents: 106500, net_cents: 3000, statement_count: 2 }],
      });
    }
    if (path === "/api/admin/coach-pay/mine/per-10/pdf") return route.fulfill({ status: 200, contentType: "application/pdf", body: "%PDF-1.4" });
    return json(route, {});
  });

  await page.goto("/admin/my-pay");
  const statement = page.getByTestId("my-pay-statement");
  await expect(statement).toContainText("Οκτώβριος 2026");
  await expect(statement.getByTestId("my-pay-total")).toContainText("510,00");
  await expect(statement.getByTestId("my-pay-gross-net")).toHaveText(/Μικτά 480,00\s€ · Καθαρά 30,00\s€/);
  await expect(statement.getByTestId("net-mark")).toBeVisible();

  const download = page.waitForEvent("download");
  await statement.getByTestId("my-pay-pdf").click();
  expect((await download).suggestedFilename()).toBe("pay-statement-2026-10-01-2026-10-31.pdf");

  const history = page.getByTestId("my-pay-history");
  await history.getByTestId("my-pay-period").filter({ hasText: "Σεπτέμβριος 2026" }).click();
  await expect(page.getByTestId("my-pay-statement")).toContainText("Σεπτέμβριος 2026");
});
