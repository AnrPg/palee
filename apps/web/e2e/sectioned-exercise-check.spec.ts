import { expect, test } from "./support/test";
import { draftId, json, stubCoach } from "./support/structured-wod";

// ADR-671: the editor with sections (WOD assistant off) checks the exercises
// before publishing, like the free-text editor: every found exercise is
// answered «Ναι»/«Όχι», and a «Ναι» links the words in their own section.
// A check that cannot run says so instead of publishing silently.

const doc = (lines: string[]) => ({
  type: "doc",
  content: lines.map((text) => ({ type: "paragraph", content: [{ type: "text", text }] })),
});

const sectionedDraft = {
  id: draftId,
  status: "draft",
  title: "Saturday",
  type: "crossfit",
  authoring_mode: "sectioned_text",
  free_text_body: null,
  dsl_source_revision: 1,
  available_scale_levels: [],
  sections: [
    {
      name: "",
      free_text_body: "21-15-9\nThrustr",
      free_text_document: doc(["21-15-9", "Thrustr"]),
      timer_preset: { format: "untimed" },
      exercises: [],
    },
  ],
  draft_data: { authoring_mode: "sectioned_text" },
};

const thrusterMatch = {
  id: "0:1:0:7",
  section: 0,
  line: 1,
  from: 0,
  to: 7,
  typed: "Thrustr",
  folded: "thrustr",
  exercise_ref: "thruster",
  label: "Thruster",
  kind: "fuzzy",
  remembered: false,
  muscles: [{ id: "quadriceps", role: "primary" }],
  qualities: [],
};

async function openEditor(page: Parameters<typeof stubCoach>[0]) {
  const server = await stubCoach(page, sectionedDraft);
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) => json(route, { wod_assistant_enabled: false }));
  await page.route("**/api/**/admin/workouts/frequent-timers", (route) => json(route, { presets: [] }));
  await page.goto(`/admin/workouts/new?draft=${draftId}`);
  await expect(page.getByTestId("text-section").first()).toContainText("Thrustr");
  return server;
}

const published = (saves: Record<string, unknown>[]) => saves.filter((save) => "expected_source_revision" in save && "sections" in save);

test("sections: found exercises are confirmed before publishing and linked in their section", async ({ page }) => {
  const decisions: unknown[] = [];
  const server = await openEditor(page);
  await page.route(`**/api/**/admin/workouts/${draftId}/exercise-matches`, (route) => json(route, { matches: [thrusterMatch] }));
  await page.route(`**/api/**/admin/workouts/${draftId}/exercise-matches/decisions`, (route) => {
    decisions.push(route.request().postDataJSON());
    return json(route, { goals_updated: false });
  });

  const publish = page.getByRole("button", { name: "Δημοσίευση προπόνησης", exact: true });
  await expect(publish).toBeEnabled();
  await publish.click();

  const dialog = page.getByTestId("exercise-matches-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Thrustr");
  const yes = dialog.getByRole("button", { name: "Ναι", exact: true });
  await expect(yes).toBeVisible();
  await yes.click();
  const confirm = dialog.getByRole("button", { name: "Δημοσίευση", exact: true });
  await expect(confirm).toBeEnabled();
  await confirm.click();

  await expect.poll(() => decisions.length).toBe(1);
  await expect
    .poll(() => {
      const publishBody = server.saves.at(-1) as { sections?: Array<{ free_text_document?: unknown }> } | undefined;
      return JSON.stringify(publishBody?.sections?.[0]?.free_text_document ?? null);
    })
    .toContain('"ref":"thruster"');
  expect(published(server.saves).length).toBeGreaterThan(0);
});

test("sections: a check that cannot run asks before publishing without it", async ({ page }) => {
  const server = await openEditor(page);
  await page.route(`**/api/**/admin/workouts/${draftId}/exercise-matches`, (route) => json(route, { code: "unavailable" }, 503));

  const publish = page.getByRole("button", { name: "Δημοσίευση προπόνησης", exact: true });
  await expect(publish).toBeEnabled();
  await publish.click();

  const notice = page.getByTestId("exercise-check-failed");
  await expect(notice).toBeVisible();
  const anyway = notice.getByRole("button", { name: "Δημοσίευση χωρίς έλεγχο" });
  await expect(anyway).toBeEnabled();
  const before = server.saves.length;
  await anyway.click();
  await expect.poll(() => server.saves.length).toBeGreaterThan(before);
});
