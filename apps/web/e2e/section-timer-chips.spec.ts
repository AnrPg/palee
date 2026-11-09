import { expect, test } from "./support/test";
import { chooseOption } from "./support/select";
import { draftId, json, stubCoach } from "./support/structured-wod";

// ADR-571: a text section's timer is «Χωρίς χρόνο» until the coach picks
// another; the chips are the coach's three most used timers, then «Χωρίς
// χρόνο», then a dropdown (another colour, with its arrow) with every format.

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

test("a section runs «Χωρίς χρόνο» unless the coach picks one of their timers", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) => json(route, { wod_assistant_enabled: false }));
  await page.route("**/api/**/admin/workouts/frequent-timers", (route) =>
    json(route, {
      presets: [
        { preset: { format: "emom", interval_seconds: 60, rounds: 4 }, source: "author", uses: 7 },
        { preset: { format: "amrap", duration_seconds: 600 }, source: "author", uses: 5 },
        { preset: { format: "amrap", duration_seconds: 1200 }, source: "gym", uses: 3 },
      ],
    }),
  );
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const section = page.getByTestId("text-section").first();
  const timer = section.getByRole("button", { name: /Χωρίς χρόνο/ });
  await expect(timer).toBeVisible();
  await timer.click();

  await expect(section.getByTestId("timer-chip")).toHaveText(["EMOM 4", "AMRAP 10", "AMRAP 20"]);
  await expect(section.getByTestId("timer-chip-no-time")).toHaveAttribute("aria-pressed", "true");
  const dropdown = section.getByTestId("timer-format-select");
  await expect(dropdown).toContainText("Χωρίς χρόνο");
  await expect(dropdown.locator("svg")).toBeVisible();

  await section.getByRole("button", { name: "EMOM 4" }).click();
  await expect(section.getByRole("button", { name: "EMOM 4" })).toHaveAttribute("aria-pressed", "true");
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "emom", rounds: 4 })]);

  await chooseOption(page, dropdown, "tabata");
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "tabata" })]);

  await section.getByTestId("timer-chip-no-time").click();
  await expect.poll(() => sectionTimers(server.saves.at(-1))).toEqual([expect.objectContaining({ format: "untimed" })]);
});
