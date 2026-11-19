import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { WodAtlasView } from "./WodAtlasView";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/anatomy/renderer/figure-controller", () => ({ createFigure: () => new Promise(() => undefined) }));
vi.mock("@/lib/anatomy/renderer/thumbs", () => ({ renderThumb: () => new Promise(() => undefined) }));

const muscles = [
  { id: "quadriceps", role: "primary" as const },
  { id: "glutes", role: "secondary" as const },
];

function wrap(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  apiRequest.mockReset();
  apiRequest.mockImplementation(async (path: string) => {
    if (path.includes("/programme-load")) {
      return {
        scheduled_class_id: "class-1",
        days: 7,
        from: "2026-11-12",
        to: "2026-11-18",
        wods: 3,
        muscles: [
          { id: "quadriceps", wods: 2, primary: 2, secondary: 0, stabilizer: 0, dates: ["2026-11-16", "2026-11-17"] },
          { id: "latissimus-dorsi", wods: 1, primary: 1, secondary: 0, stabilizer: 0, dates: ["2026-11-18"] },
        ],
      };
    }
    if (path.startsWith("/staff/clients/")) {
      return {
        range: "4w",
        weeks: 4,
        from: "2026-10-23",
        to: "2026-11-19",
        taxonomy_version: 1,
        thresholds: { medium: 3, high: 8 },
        sessions: 4,
        felt_entries: 0,
        exercises: { recognized: 4, unrecognized: 0 },
        nodes: [{ id: "quadriceps", kind: "group", sets: 20, per_week: 5, level: "medium", felt: 0, top_exercises: [] }],
      };
    }
    return { node_id: "x", videos_included: true, exercises: [] };
  });
});

describe("WodAtlasView", () => {
  it("in the Αρχείο shows the WOD alone: no coverage, no load, no link to a journal", async () => {
    wrap(<WodAtlasView muscles={muscles} context={{ kind: "library" }} />);
    expect(screen.getByRole("radio", { name: "This WOD" })).toBeChecked();
    expect(screen.getAllByRole("radio").map((radio) => radio.textContent)).toEqual(["This WOD", "Explore"]);
    expect(screen.queryByTestId("wod-atlas-full")).toBeNull();
    fireEvent.click(within(screen.getByTestId("atlas-wod-muscles")).getByRole("button", { name: /Quadriceps/ }));
    expect(await screen.findByTestId("atlas-wod-role")).toHaveTextContent("In this WOD: Primary");
    await waitFor(() => expect(apiRequest).toHaveBeenCalledWith("/anatomy/nodes/quadriceps/exercises", { token: "token" }));
    expect(apiRequest).not.toHaveBeenCalledWith(expect.stringContaining("/me/atlas"), expect.anything());
  });

  it("for a class adds «Programme load» of the same class's previous 7 days", async () => {
    wrap(<WodAtlasView muscles={muscles} context={{ kind: "class", classId: "class-1" }} />);
    fireEvent.click(screen.getByRole("radio", { name: "Programme load" }));
    const list = await screen.findByTestId("wod-atlas-load");
    expect(apiRequest).toHaveBeenCalledWith("/admin/schedule/slots/class-1/programme-load", { token: "token" });
    expect(list).toHaveTextContent("Quadriceps2 WODs");
    expect(list).toHaveTextContent("Latissimus dorsi1 WOD");
    expect(screen.getByTestId("wod-atlas-load-repeat")).toHaveTextContent("Already 2 or more times: Quadriceps.");
    fireEvent.click(within(list).getByRole("button", { name: /Quadriceps/ }));
    expect(await screen.findByTestId("wod-atlas-load-line")).toHaveTextContent("In 2 WODs of the class in the previous 7 days: Mon and Tue.");
  });

  it("for an assigned WOD shows each athlete's coverage, only through the coach's read", async () => {
    wrap(
      <WodAtlasView
        muscles={muscles}
        context={{ kind: "athlete", athletes: [{ id: "a-1", name: "Nikos" }, { id: "a-2", name: "Maria" }] }}
      />,
    );
    fireEvent.click(screen.getByRole("radio", { name: "Coverage: Nikos" }));
    const list = await screen.findByTestId("wod-atlas-athlete");
    expect(apiRequest).toHaveBeenCalledWith("/staff/clients/a-1/atlas?range=4w", { token: "token" });
    await waitFor(() => expect(list).toHaveTextContent("QuadricepsMedium"));
    expect(list).toHaveTextContent("GlutesNone");
    fireEvent.click(screen.getByRole("button", { name: "Maria" }));
    await waitFor(() => expect(apiRequest).toHaveBeenCalledWith("/staff/clients/a-2/atlas?range=4w", { token: "token" }));
  });
});
