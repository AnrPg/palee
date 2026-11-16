import { expect, test } from "./support/test";
import { draftId, json, stubCoach } from "./support/structured-wod";

// ADR-650: the WOD formats are offered while typing, above the exercises,
// and the timer follows the text («AMRAP 12» picks AMRAP 12) until the coach
// changes it by hand; «Από το κείμενο» gives it back to the text.

const sectionedDraft = {
  id: draftId,
  status: "draft",
  title: "",
  type: null,
  authoring_mode: "sectioned_text",
  free_text_body: null,
  dsl_source_revision: 1,
  available_scale_levels: [],
  sections: [{ name: "Ενότητα 1", free_text_body: "", timer_preset: null, exercises: [] }],
  draft_data: { authoring_mode: "sectioned_text" },
};

const sectionTimers = (save: Record<string, unknown> | undefined) =>
  ((save?.sections as Array<{ timer_preset: unknown }> | undefined) ?? []).map((section) => section.timer_preset);

test("a section's text sets its timer, a change by hand wins, «Από το κείμενο» restores it", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) => json(route, { wod_assistant_enabled: false }));
  await page.route("**/api/**/admin/workouts/frequent-timers", (route) =>
    json(route, { presets: [{ preset: { format: "amrap", duration_seconds: 720 }, source: "author", uses: 4 }] }),
  );
  await page.route("**/api/**/me/exercise-suggestions**", (route) => json(route, { groups: [] }));
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const section = page.getByTestId("text-section").first();
  const text = section.getByRole("textbox", { name: /Κείμενο/ });
  await expect(text).toBeVisible();
  await text.click();
  await page.keyboard.type("am");

  const list = page.getByTestId("editor-exercise-suggestions");
  await expect(list).toBeVisible();
  await expect(list.getByRole("option").first()).toContainText("AMRAP 12");
  await expect(list.getByRole("option").first()).toContainText("Μορφή · συχνό σου");
  await page.keyboard.press("Tab");

  const timer = section.getByTestId("section-timer-button");
  await expect(timer).toContainText("AMRAP");
  await expect(timer).toContainText("από το κείμενο");
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "amrap", duration_seconds: 720 })]);

  await expect(timer).toBeEnabled();
  await timer.click();
  const noTime = section.getByTestId("timer-chip-no-time");
  await expect(noTime).toBeVisible();
  await noTime.click();
  await expect(timer).not.toContainText("από το κείμενο");
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "untimed" })]);

  const restore = section.getByTestId("text-timer-restore");
  await expect(restore).toBeVisible();
  await restore.click();
  await expect(timer).toContainText("από το κείμενο");
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "amrap", duration_seconds: 720 })]);
});

test("«Πώς γράφω το χρονόμετρο;» opens the formats help, where a line can be tried", async ({ page }) => {
  await stubCoach(page, sectionedDraft);
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) => json(route, { wod_assistant_enabled: false }));
  await page.route("**/api/**/admin/workouts/frequent-timers", (route) => json(route, { presets: [] }));
  await page.route("**/api/**/me/exercise-suggestions**", (route) => json(route, { groups: [] }));
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const section = page.getByTestId("text-section").first();
  const timer = section.getByTestId("section-timer-button");
  await expect(timer).toBeVisible();
  await expect(timer).toBeEnabled();
  await timer.click();
  const open = section.getByTestId("wod-formats-help-button");
  await expect(open).toBeVisible();
  await expect(open).toBeEnabled();
  await open.click();

  const help = page.getByTestId("wod-formats-help");
  await expect(help).toBeVisible();
  const input = help.getByTestId("wod-formats-help-try");
  await expect(input).toBeVisible();
  await input.fill("EMOM 10");
  await expect(help.getByTestId("wod-formats-help-chip")).toContainText("EMOM");
  await expect(help.getByTestId("wod-formats-help-result")).toContainText("10 φορές");
  await page.keyboard.press("Escape");
  await expect(help).toBeHidden();
});
