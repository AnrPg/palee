import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";
import en from "../../../messages/en.json";

import type { ClassTypeRecord } from "@/api/schedule";

import { ClassTypeSettings } from "./ClassTypeSettings";

const api = vi.hoisted(() => ({
  types: [] as ClassTypeRecord[],
  update: vi.fn(),
}));

vi.mock("@/api/schedule", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/schedule")>();
  return {
    ...actual,
    listAdminClassTypes: () => Promise.resolve(api.types),
    updateClassType: (...args: unknown[]) => {
      api.update(...args);
      return Promise.resolve(api.types[0]);
    },
    createClassType: vi.fn(),
    archiveClassType: vi.fn(),
  };
});

function type(overrides: Partial<ClassTypeRecord> = {}): ClassTypeRecord {
  return {
    id: "ct-1",
    name: "Bodybuilding",
    slug: "bodybuilding",
    sort_order: 0,
    archived_at: null,
    credit_cost: 1,
    kind: "class",
    levels: [],
    audiences: [],
    ...overrides,
  };
}

function renderSettings(locale: "en" | "el" = "en") {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : el}>
        <ClassTypeSettings token="token" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

async function openAdvanced() {
  await screen.findByText("Bodybuilding");
  fireEvent.click(screen.getByRole("button", { name: /Advanced/ }));
}

describe("ClassTypeSettings (ADR-490)", () => {
  beforeEach(() => {
    api.types = [type()];
    api.update.mockReset();
  });

  it("keeps «Event» under «Advanced», with a badge on the card when it is on", async () => {
    api.types = [type({ kind: "event" })];
    renderSettings();
    await screen.findByText("Bodybuilding");

    expect(screen.queryByRole("checkbox", { name: "Event" })).toBeNull();
    expect(screen.getByText("Event")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: /Advanced/ }));
    const checkbox = screen.getByRole("checkbox", { name: "Event" }) as HTMLInputElement;
    expect(checkbox.checked).toBe(true);

    fireEvent.click(checkbox);
    await waitFor(() => expect(api.update).toHaveBeenCalled());
    expect(api.update.mock.calls[0][2]).toMatchObject({ kind: "class" });
  });

  it("picks several levels and shows «All levels» when none is picked", async () => {
    api.types = [type({ levels: ["beginner"] })];
    renderSettings();
    await openAdvanced();

    const group = screen.getByRole("group", { name: "Level" });
    expect(within(group).getByRole("button", { name: "Beginners" }).getAttribute("aria-pressed")).toBe("true");
    expect(within(group).queryByText("All levels")).toBeNull();

    fireEvent.click(within(group).getByRole("button", { name: "Intermediate" }));
    await waitFor(() => expect(api.update).toHaveBeenCalled());
    expect(api.update.mock.calls[0][2]).toMatchObject({ levels: ["beginner", "intermediate"] });
  });

  it("says «All levels» for a class type without levels", async () => {
    renderSettings();
    await openAdvanced();
    expect(within(screen.getByRole("group", { name: "Level" })).getByText("All levels")).toBeTruthy();
  });

  it("gives every advanced option a tooltip and an info box that a press opens and closes", async () => {
    renderSettings();
    await openAdvanced();

    const infoButtons = screen.getAllByRole("button", { name: /^What is «/ });
    expect(infoButtons).toHaveLength(4);
    expect(screen.getAllByRole("tooltip").map((tip) => tip.textContent)).toEqual([
      en.ClassTypeOptions.event_tip,
      en.ClassTypeOptions.visits_tip,
      en.ClassTypeOptions.level_tip,
      en.ClassTypeOptions.audience_tip,
    ]);

    const levelInfo = screen.getByRole("button", { name: "What is «Level»?" });
    expect(screen.queryByRole("note")).toBeNull();
    fireEvent.click(levelInfo);
    const note = screen.getByRole("note");
    expect(levelInfo.getAttribute("aria-expanded")).toBe("true");
    expect(note.textContent).toContain(en.ClassTypeOptions.level_what);
    expect(note.textContent).toContain(en.ClassTypeOptions.level_members);
    expect(note.textContent).toContain(en.ClassTypeOptions.level_when);

    fireEvent.click(levelInfo);
    expect(screen.queryByRole("note")).toBeNull();
  });

  it("speaks Greek with the canonical names", async () => {
    renderSettings("el");
    await screen.findByText("Bodybuilding");
    fireEvent.click(screen.getByRole("button", { name: /Προχωρημένα/ }));
    expect(screen.getByRole("checkbox", { name: "Εκδήλωση" })).toBeTruthy();
    const group = screen.getByRole("group", { name: "Επίπεδο" });
    expect(within(group).getAllByRole("button").map((button) => button.textContent)).toEqual([
      "Αρχάριοι",
      "Μεσαίοι",
      "Προχωρημένοι",
    ]);
    expect(within(group).getByText("Όλα τα επίπεδα")).toBeTruthy();
  });
});
