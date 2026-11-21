import { expect, test } from "./support/test";
import { draftId, json, stubCoach } from "./support/structured-wod";

// ADR-275 / ADR-690: a WOD's «Τύπος προπόνησης» comes from the Palee kinds
// (grouped in families, translated, limited to the kinds the box offers),
// the kinds the Palee team added and the box's own types. A WOD has one or
// more types and none is the main one; a name the box lacks becomes a box
// type from the same field.

const boxKindId = "4f1c2b7e-1d2c-4a1b-9c3d-2e1f0a9b8c7d";

const sectionedDraft = {
  id: draftId,
  status: "draft",
  title: "",
  type: null,
  types: [],
  authoring_mode: "sectioned_text",
  free_text_body: null,
  dsl_source_revision: 1,
  available_scale_levels: [],
  sections: [{ name: "Ενότητα 1", free_text_body: "", timer_preset: null, exercises: [] }],
  draft_data: { authoring_mode: "sectioned_text" },
};

type Catalogue = { additions: unknown[]; box: Record<string, unknown>[] };

async function settings(page: Parameters<typeof stubCoach>[0], workoutTypes: string[], catalogue: Catalogue = { additions: [], box: [] }) {
  await page.route("**/api/**/admin/workouts/authoring-settings", (route) =>
    json(route, { wod_assistant_enabled: true, workout_types: workoutTypes, workout_kinds: catalogue }),
  );
}

test("the field offers the box's types in Greek, by family, and takes several", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await settings(page, ["crossfit", "strength", "boxing", "muay_thai", "dance"]);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const field = page.getByTestId("workout-types-field").first();
  const search = field.getByTestId("workout-types-search");
  await expect(search).toBeVisible();
  await search.click();
  const list = page.getByRole("listbox");
  await expect(list.getByRole("option")).toHaveText(["CrossFit", "Δύναμη", "Πυγμαχία", "Muay Thai", "Χορός"]);
  await expect(list).toContainText("Μαχητικά αθλήματα");
  await expect(list.getByText("crossfit", { exact: true })).toHaveCount(0);

  await search.fill("muay");
  await list.getByRole("option", { name: "Muay Thai" }).click();
  await expect(field.getByTestId("workout-type-chip")).toHaveText([/Muay Thai/]);

  // «+ Κι άλλος τύπος»: a second type, every type counts the same.
  const more = field.getByTestId("workout-type-add-more");
  await expect(more).toBeVisible();
  await more.click();
  const again = field.getByTestId("workout-types-search");
  await expect(again).toBeVisible();
  await again.fill("δύνα");
  await page.getByRole("listbox").getByRole("option", { name: "Δύναμη" }).click();
  await expect(field.getByTestId("workout-type-chip")).toHaveCount(2);
  await expect.poll(() => server.saves.at(-1)?.types).toEqual(["strength", "muay_thai"]);

  // A chip's × takes the type off again.
  await field.getByRole("button", { name: /Δύναμη/ }).click();
  await expect.poll(() => server.saves.at(-1)?.types).toEqual(["muay_thai"]);
});

test("a WOD keeps a type the box has since hidden", async ({ page }) => {
  await stubCoach(page, { ...sectionedDraft, type: "yoga", types: ["yoga"] });
  await settings(page, ["crossfit"]);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const field = page.getByTestId("workout-types-field").first();
  await expect(field.getByTestId("workout-type-chip")).toHaveText([/Γιόγκα/]);
});

test("a new name becomes a box type after «Μήπως εννοείς…» and a family", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await settings(page, ["crossfit", "hyrox", "strength"]);
  const created: Record<string, unknown>[] = [];
  await page.route("**/api/**/admin/workout-kinds", async (route) => {
    if (route.request().method() !== "POST") return json(route, { additions: [], box: [] });
    const body = route.request().postDataJSON() as Record<string, unknown>;
    created.push(body);
    return json(
      route,
      { workout_kind: { id: boxKindId, ref: `box:${boxKindId}`, label: body.label, family: body.family, status: "active", merged_into: null } },
      201,
    );
  });
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const field = page.getByTestId("workout-types-field").first();
  const search = field.getByTestId("workout-types-search");
  await expect(search).toBeVisible();
  await search.fill("Hyroks");
  await page.getByRole("listbox").getByRole("option", { name: /Νέος τύπος «Hyroks»/ }).click();

  const dialog = page.getByTestId("new-workout-type-dialog");
  await expect(dialog).toBeVisible();
  // A close Palee kind comes first; its family is the likeliest one.
  await expect(dialog.getByTestId("new-workout-type-close")).toContainText("HYROX");
  await expect(dialog.getByRole("radio", { name: "Λειτουργική & CrossFit" })).toHaveAttribute("aria-checked", "true");

  await dialog.getByTestId("new-workout-type-name").fill("Hyrox Sim");
  await dialog.getByRole("radio", { name: "Αντοχή" }).click();
  const create = dialog.getByTestId("new-workout-type-create");
  await expect(create).toBeEnabled();
  await create.click();

  await expect.poll(() => created).toEqual([{ label: "Hyrox Sim", family: "endurance" }]);
  await expect(dialog).toHaveCount(0);
  await expect.poll(() => server.saves.at(-1)?.types).toEqual([`box:${boxKindId}`]);
});

test("in a sectioned WOD each section has types and the WOD's are their union", async ({ page }) => {
  const server = await stubCoach(page, sectionedDraft);
  await settings(page, ["crossfit", "strength", "running"]);
  await page.goto(`/admin/workouts/new?draft=${draftId}`);

  const sectionField = page.getByTestId("section-types-field").first();
  const search = sectionField.getByTestId("workout-types-search");
  await expect(search).toBeVisible();
  await search.fill("τρέξ");
  await page.getByRole("listbox").getByRole("option").first().click();

  await expect.poll(() => (server.saves.at(-1)?.sections as { types?: string[] }[] | undefined)?.[0]?.types).toEqual(["running"]);
  await expect.poll(() => server.saves.at(-1)?.types).toEqual(["running"]);
  // The WOD's own field now shows the union, read only.
  const wodField = page.getByTestId("workout-types-field").first();
  await expect(wodField.getByTestId("workout-types-search")).toHaveCount(0);
  await expect(wodField.getByTestId("workout-type-chip")).toHaveCount(1);
});
