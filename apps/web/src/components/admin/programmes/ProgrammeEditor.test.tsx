import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import en from "../../../../messages/en.json";

import type { StaffProgramme } from "@/api/programmes";
import type { WorkoutRecord } from "@/api/workouts";

import { ProgrammeEditor } from "./ProgrammeEditor";

const api = vi.hoisted(() => ({
  programme: null as unknown as StaffProgramme,
  workouts: [] as WorkoutRecord[],
  update: vi.fn(),
  removeCover: vi.fn(),
}));

vi.mock("@/api/programmes", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/programmes")>();
  return {
    ...actual,
    fetchStaffProgramme: () => Promise.resolve(api.programme),
    updateProgramme: (_token: string, _id: string, body: Record<string, unknown>) => {
      api.update(body);
      api.programme = { ...api.programme, ...body } as StaffProgramme;
      return Promise.resolve(api.programme);
    },
  };
});
vi.mock("@/api/workouts", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/workouts")>()),
  listAdminWorkouts: () => Promise.resolve(api.workouts),
}));
vi.mock("@/api/programme-covers", () => ({
  removeProgrammeCover: (...args: unknown[]) => {
    api.removeCover(...args);
    return Promise.resolve({ ...api.programme, cover: null, cover_url: null });
  },
  requestProgrammeCoverUpload: vi.fn(),
  completeProgrammeCover: vi.fn(),
  setProgrammeCover: vi.fn(),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationSlug: () => "kypseli",
  adminHref: (path: string) => path,
}));

const workout = (id: string, title: string, type: string, seconds?: number) =>
  ({ id, title, type, status: "published", available_scale_levels: [], sections: [], estimated_duration_seconds: seconds }) as WorkoutRecord;

function programme(overrides: Partial<StaffProgramme> = {}): StaffProgramme {
  return {
    id: "p-1",
    title: "Strength in 6 weeks",
    summary: null,
    level: "intermediate",
    goal: "strength",
    status: "draft",
    draft_weeks: 2,
    draft_days: [
      { day: 0, workout_id: "w-squat" },
      { day: 2, workout_id: "w-fran" },
    ],
    currency: "EUR",
    listing: "box",
    preview_days: 3,
    price_cents: 0,
    refund_policy: "before_start",
    readiness: [],
    equipment: [],
    equipment_removed: [],
    facts: { equipment: ["barbell", "rower"], minutes_per_session: 50 },
    cover: null,
    cover_url: null,
    ...overrides,
  } as StaffProgramme;
}

function setDesktop(desktop: boolean) {
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    writable: true,
    value: (query: string) => ({
      matches: desktop && query.includes("min-width: 1024px"),
      media: query,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      addListener: () => undefined,
      removeListener: () => undefined,
      onchange: null,
      dispatchEvent: () => false,
    }),
  });
}

function renderEditor(locale: "en" | "el" = "en") {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : el}>
        <ProgrammeEditor id="p-1" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const lastSaved = () => api.update.mock.calls.at(-1)?.[0] as Record<string, unknown> | undefined;

beforeEach(() => {
  api.programme = programme();
  api.workouts = [workout("w-squat", "Back squat 5×5", "strength", 3000), workout("w-fran", "Fran", "crossfit"), workout("w-row", "Row 5×500 m", "rowing")];
  api.update.mockReset();
  api.removeCover.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("ProgrammeEditor on a phone (board 1κ A)", () => {
  beforeEach(() => setDesktop(false));

  it("shows one week as day rows with the week strip, and marks an empty week", async () => {
    renderEditor();
    expect(await screen.findByTestId("programme-weeks-phone")).toBeInTheDocument();
    expect(screen.getByTestId("programme-week-summary")).toHaveTextContent("2 workouts · 5 rest days");
    await waitFor(() => expect(screen.getByTestId("programme-day-0")).toHaveTextContent("Back squat 5×5"));
    expect(screen.getByTestId("programme-day-0")).toHaveTextContent("Strength · ~50′");
    expect(screen.getByTestId("programme-day-1")).toHaveTextContent("Rest");
    expect(within(screen.getByTestId("programme-week-chip-1")).getByText("empty")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("programme-week-chip-1"));
    expect(screen.getByTestId("programme-week-summary")).toHaveTextContent("Empty week");
  });

  it("opens the library for a day and saves the WOD picked there", async () => {
    renderEditor();
    fireEvent.click(await screen.findByTestId("programme-day-1"));
    const sheet = await screen.findByTestId("programme-day-sheet");
    expect(within(sheet).getByText("Wk 1 · Day 2")).toBeInTheDocument();
    expect(within(sheet).getByText("Recent")).toBeInTheDocument();
    fireEvent.click(within(sheet).getByTestId("programme-pick-w-row"));
    expect(screen.queryByTestId("programme-day-sheet")).not.toBeInTheDocument();
    expect(screen.getByTestId("programme-day-1")).toHaveTextContent("Row 5×500 m");
    expect(screen.getByTestId("programme-notice")).toHaveTextContent("Added to day 2");
    await waitFor(() => expect(lastSaved()?.draft_days).toEqual([
      { day: 0, workout_id: "w-squat" },
      { day: 1, workout_id: "w-row" },
      { day: 2, workout_id: "w-fran" },
    ]), { timeout: 3000 });
  });

  it("makes a day a rest day from its sheet", async () => {
    renderEditor();
    fireEvent.click(await screen.findByTestId("programme-day-2"));
    fireEvent.click(await screen.findByTestId("programme-day-rest"));
    expect(screen.getByTestId("programme-day-2")).toHaveTextContent("Rest");
  });

  it("copies a week to the next one, filling only its empty days", async () => {
    api.programme = programme({ draft_days: [{ day: 0, workout_id: "w-squat" }, { day: 2, workout_id: "w-fran" }, { day: 9, workout_id: "w-row" }] });
    renderEditor();
    fireEvent.click(await screen.findByTestId("programme-week-actions"));
    fireEvent.click(await screen.findByTestId("programme-copy-next"));
    expect(screen.getByTestId("programme-notice")).toHaveTextContent("Week 2: 1 day copied");
    expect(screen.getByTestId("programme-day-7")).toHaveTextContent("Back squat 5×5");
    expect(screen.getByTestId("programme-day-9")).toHaveTextContent("Row 5×500 m");
  });

  it("asks before deleting a week that has WODs", async () => {
    renderEditor();
    fireEvent.click(await screen.findByTestId("programme-week-actions"));
    fireEvent.click(await screen.findByTestId("programme-delete-week"));
    fireEvent.click(await screen.findByTestId("programme-week-delete-confirm"));
    expect(screen.queryByTestId("programme-week-chip-1")).not.toBeInTheDocument();
    expect(screen.getByTestId("programme-day-0")).toHaveTextContent("Rest");
  });

  it("lists what is missing and takes the coach to the summary", async () => {
    renderEditor();
    const bar = await screen.findByTestId("programme-readiness-bar");
    expect(bar).toHaveTextContent("2 things missing");
    fireEvent.click(within(bar).getByTestId("programme-readiness-open"));
    const sheet = await screen.findByTestId("programme-readiness");
    expect(sheet).toHaveTextContent("Week 2 has no WOD");
    fireEvent.click(within(sheet).getByTestId("programme-readiness-summary"));
    await waitFor(() => expect(screen.getByTestId("programme-summary")).toHaveFocus());
  });

  it("speaks Greek", async () => {
    renderEditor("el");
    expect(await screen.findByTestId("programme-readiness-bar")).toHaveTextContent("Λείπουν 2 πράγματα");
    expect(screen.getByTestId("programme-week-summary")).toHaveTextContent("2 προπονήσεις · 5 ξεκούραση");
  });
});

describe("ProgrammeEditor on a large screen (board 1μ A)", () => {
  beforeEach(() => setDesktop(true));

  const cell = (day: number) => screen.getByTestId(`programme-cell-${day}`);

  it("shows every week in a grid with the library and the readiness line", async () => {
    renderEditor();
    expect(await screen.findByTestId("programme-weeks-desktop")).toBeInTheDocument();
    expect(screen.getByRole("grid", { name: "Weeks and days of the training programme" })).toBeInTheDocument();
    expect(screen.getByTestId("programme-readiness-banner")).toHaveTextContent("Before publishing:");
    expect(await screen.findByTestId("programme-library-w-row")).toHaveTextContent("Row 5×500 m");
    expect(cell(0)).toHaveAccessibleName("Week 1, day 1: Back squat 5×5");
    expect(screen.getByText("Shift")).toBeInTheDocument();
  });

  it("places a WOD by picking a day and then the WOD", async () => {
    renderEditor();
    await screen.findByTestId("programme-library-w-row");
    fireEvent.click(cell(3));
    expect(cell(3)).toHaveAttribute("aria-selected", "true");
    fireEvent.click(screen.getByTestId("programme-library-w-row"));
    expect(cell(3)).toHaveTextContent("Row 5×500 m");
  });

  it("places a chosen WOD with the keyboard: Enter on the WOD, arrows to a day, Enter", async () => {
    renderEditor();
    await screen.findByTestId("programme-library-w-fran");
    fireEvent.click(screen.getByTestId("programme-library-w-fran"));
    expect(screen.getByTestId("programme-library-w-fran")).toHaveAttribute("aria-pressed", "true");
    act(() => cell(0).focus());
    fireEvent.keyDown(cell(0), { key: "ArrowDown" });
    await waitFor(() => expect(cell(7)).toHaveFocus());
    fireEvent.keyDown(cell(7), { key: "Enter" });
    expect(cell(7)).toHaveTextContent("Fran");
  });

  it("drops a WOD dragged from the library onto a day", async () => {
    renderEditor();
    const item = await screen.findByTestId("programme-library-w-squat");
    const data = new Map<string, string>();
    const dataTransfer = {
      setData: (type: string, value: string) => data.set(type, value),
      getData: (type: string) => data.get(type) ?? "",
      get types() {
        return [...data.keys()];
      },
      effectAllowed: "",
      dropEffect: "",
    };
    fireEvent.dragStart(item, { dataTransfer });
    fireEvent.dragOver(cell(5), { dataTransfer });
    fireEvent.drop(cell(5), { dataTransfer });
    expect(cell(5)).toHaveTextContent("Back squat 5×5");
  });

  it("copies a day with Ctrl C, pastes it on Shift-selected days with Ctrl V, and Del rests them", async () => {
    renderEditor();
    await screen.findByTestId("programme-library-w-squat");
    act(() => cell(0).focus());
    fireEvent.keyDown(cell(0), { key: "c", ctrlKey: true });
    expect(screen.getByTestId("programme-notice")).toHaveTextContent("Week 1, day 1 copied");
    fireEvent.click(cell(8));
    fireEvent.click(cell(10), { shiftKey: true });
    expect(screen.getByTestId("programme-selection")).toHaveTextContent("3 days picked");
    fireEvent.keyDown(cell(10), { key: "v", metaKey: true });
    [8, 9, 10].forEach((day) => expect(cell(day)).toHaveTextContent("Back squat 5×5"));
    fireEvent.keyDown(cell(10), { key: "Delete" });
    [8, 9, 10].forEach((day) => expect(cell(day)).toHaveTextContent("Rest"));
    expect(screen.getByTestId("programme-notice")).toHaveTextContent("3 days are now rest days");
  });

  it("copies a week down from its row and goes to the first missing thing", async () => {
    renderEditor();
    await screen.findByTestId("programme-library-w-squat");
    fireEvent.click(screen.getByTestId("programme-copy-next-0"));
    expect(cell(7)).toHaveTextContent("Back squat 5×5");
    expect(screen.getByTestId("programme-readiness-banner")).not.toHaveTextContent("has no WOD");
    fireEvent.click(screen.getByTestId("programme-readiness-first"));
    await waitFor(() => expect(screen.getByTestId("programme-summary")).toHaveFocus());
  });
});

describe("ProgrammeEditor details", () => {
  beforeEach(() => setDesktop(true));

  async function openDetails() {
    renderEditor();
    await screen.findByTestId("programme-weeks-desktop");
    fireEvent.click(screen.getByRole("tab", { name: "Details" }));
    return screen.findByTestId("programme-details");
  }

  it("shows the derived equipment, lets the author remove and add keys, and saves both lists", async () => {
    await openDetails();
    const equipment = screen.getByTestId("programme-equipment");
    expect(equipment).toHaveTextContent("Barbell");
    expect(screen.getByTestId("programme-minutes")).toHaveTextContent("50 min");
    fireEvent.click(screen.getByTestId("programme-equipment-remove-barbell"));
    expect(equipment).toHaveTextContent("Removed: Barbell");
    await waitFor(() => expect(lastSaved()).toEqual({ equipment_removed: ["barbell"] }), { timeout: 3000 });
  });

  it("shows the colour strip and only «Upload a photo» without a cover", async () => {
    await openDetails();
    expect(screen.getByTestId("programme-cover-upload")).toHaveTextContent("Upload a photo");
    expect(screen.queryByTestId("programme-cover-remove")).not.toBeInTheDocument();
  });

  it("removes a cover after asking", async () => {
    api.programme = programme({
      cover_url: "https://media.example/cover.webp",
      cover: {
        aspect: "16:9",
        media_id: "m-1",
        original_media_id: "m-0",
        url: "https://media.example/cover.webp",
        original_url: "https://media.example/original.webp",
        edit: null,
      },
    });
    await openDetails();
    expect(screen.getByRole("img", { name: "Cover of Strength in 6 weeks" })).toBeInTheDocument();
    expect(screen.getByTestId("programme-cover-edit")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("programme-cover-remove"));
    fireEvent.click(await screen.findByTestId("programme-cover-remove-confirm"));
    await waitFor(() => expect(api.removeCover).toHaveBeenCalledWith("tok", "p-1"));
  });

  it("shows the title error under the field", async () => {
    await openDetails();
    fireEvent.change(screen.getByTestId("programme-title"), { target: { value: "a" } });
    expect(screen.getByTestId("programme-title")).toHaveAccessibleDescription("Give it a title of at least 2 characters.");
  });
});
