import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { emptyAnalyticsFilter, type AnalyticsFilter } from "@/lib/analytics-filter";
import { readKpi, STAFF_METRICS } from "@/lib/analytics-kpi";

const LOCATION_A = "11111111-1111-4111-8111-111111111111";
const LOCATION_B = "22222222-2222-4222-8222-222222222222";
const COACH = "33333333-3333-4333-8333-333333333333";

const state = vi.hoisted(() => ({
  search: "",
  replace: vi.fn(),
  membership: { capabilities: { reset_analytics: true } } as { capabilities: Record<string, boolean> } | null,
  summary: vi.fn(),
  financeSummary: vi.fn(),
  reset: vi.fn(),
  undo: vi.fn(),
  resets: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useSearchParams: () => new URLSearchParams(state.search),
  usePathname: () => "/admin/metrics/training",
  useRouter: () => ({ replace: state.replace, push: vi.fn() }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationTimeZone: () => "Europe/Athens",
  useOrganizationSlug: () => "box",
  adminHref: (path: string) => path,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membership: state.membership }) }));
vi.mock("@/components/semantic-label", () => ({ SemanticLabel: ({ value }: { value: unknown }) => <>{String(value)}</> }));
vi.mock("@/api/analytics", () => ({
  fetchStaffAnalyticsSummary: (...args: unknown[]) => state.summary(...args),
  resetAnalyticsMetric: (...args: unknown[]) => state.reset(...args),
  undoAnalyticsMetricReset: (...args: unknown[]) => state.undo(...args),
  fetchAnalyticsResets: (...args: unknown[]) => state.resets(...args),
}));
vi.mock("@/api/finance", () => ({
  fetchFinanceAnalyticsSummary: (...args: unknown[]) => state.financeSummary(...args),
  fetchFinanceSummary: () => Promise.resolve({}),
  fetchFinanceQueues: () => Promise.resolve({ queues: {} }),
}));
vi.mock("@/components/admin/BranchFilter", () => ({
  useBranchFilter: () => ({ param: undefined }),
  BranchFilterControl: () => null,
  BranchSplits: () => null,
}));
vi.mock("@/components/admin/finance/RevenueStreamsCard", () => ({ RevenueStreamsCard: () => null }));
vi.mock("recharts", () => {
  const Empty = ({ children }: { children?: ReactNode }) => <div>{children}</div>;
  return { CartesianGrid: Empty, Line: Empty, LineChart: Empty, ResponsiveContainer: Empty, Tooltip: Empty, XAxis: Empty, YAxis: Empty };
});
vi.mock("./use-analytics-directory", () => ({
  useAnalyticsDirectory: () => ({
    locations: [
      { value: LOCATION_A, label: "Kypseli" },
      { value: LOCATION_B, label: "Pagrati" },
    ],
    classTypes: [],
    coaches: [{ value: COACH, label: "Maria" }],
    packages: [],
    packageNameByCode: new Map(),
    staffName: new Map([[COACH, "Maria"]]),
  }),
}));

import { AdminAnalytics, type AnalyticsSection } from "@/components/admin-analytics";
import { FinanceDashboard } from "@/components/admin/finance/FinanceDashboard";

import { AnalyticsFilterBar } from "./AnalyticsFilterBar";
import { AnalyticsResetHistory } from "./AnalyticsResetHistory";
import { KpiTile } from "./KpiWidgets";
import { useAnalyticsFilter } from "./use-analytics-filter";

function wrap(ui: ReactNode, client = new QueryClient({ defaultOptions: { queries: { retry: false } } })) {
  return {
    client,
    ...render(
      <QueryClientProvider client={client}>
        <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
          {ui}
        </NextIntlClientProvider>
      </QueryClientProvider>,
    ),
  };
}

/** Every staff metric with a value, a previous value and a row or two. */
function fullPayload() {
  const kpis: Record<string, unknown> = {};
  for (const [key, meta] of Object.entries(STAFF_METRICS)) {
    kpis[key] = {
      key,
      unit: meta.unit,
      kind: meta.kind,
      value: 12,
      previous: 10,
      delta: 2,
      since: null,
      suppressed: false,
      previous_suppressed: false,
      rows: meta.unit === "rows" ? [{ key: key.includes("hour") ? 18 : COACH, count: 4, people: 6, classes: 2, attendances: 9, athletes: 3, rating: 4.5, cents: 1200 }] : [],
    };
  }
  return {
    kpis,
    analytics: {
      events: { total: 3, by_category: [{ category: "classes", total: 3, events: [{ name: "class_booked", count: 3 }] }] },
      attendance: { by_status: { attended: 3 } },
      push_dispatch: { by_status: { sent: 2 } },
      communication: { by_direction: { inbound: 1 } },
    },
    feedback: { total: 2, by_rating: { "5": 2 } },
    execution: {
      started: 4,
      completed: 3,
      completion_rate: 0.75,
      abandon_points: [],
      abandon_by_format: [],
      by_format: [],
      by_source: [],
      daily: [{ date: "2026-11-01", started: 1, completed: 1 }],
    },
    totals: { active_memberships: 3 },
  };
}

function helpKeys() {
  return Array.from(document.querySelectorAll<HTMLElement>("[data-help-key]")).map((node) => node.dataset.helpKey ?? "");
}

beforeEach(() => {
  state.search = "";
  state.replace.mockReset();
  state.membership = { capabilities: { reset_analytics: true } };
  state.summary.mockReset().mockResolvedValue(fullPayload());
  state.financeSummary.mockReset().mockResolvedValue(fullPayload());
  state.reset.mockReset().mockResolvedValue({ reset: { id: "r1" } });
  state.undo.mockReset().mockResolvedValue({ reset: { id: "r1" } });
  state.resets.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("AnalyticsFilterBar", () => {
  function renderBar(filter: AnalyticsFilter, onChange = vi.fn()) {
    wrap(
      <AnalyticsFilterBar
        filter={filter}
        onChange={onChange}
        dimensions={["location_ids", "coach_ids", "genders"]}
        days={30}
        today="2026-11-04"
        page="training"
      />,
    );
    return onChange;
  }

  it("always shows the period bar and the comparison", () => {
    const onChange = renderBar(emptyAnalyticsFilter());
    const group = screen.getByRole("group", { name: "Period" });
    expect(within(group).getAllByRole("button").map((button) => button.textContent)).toEqual([
      "7 days",
      "30 days",
      "90 days",
      "This year",
      "From…to",
    ]);
    expect(screen.getByRole("button", { name: "30 days" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByText("compared with the previous 30 days")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "90 days" }));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ period: "90", from: null, to: null }));

    fireEvent.click(screen.getByRole("button", { name: "From…to" }));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ period: "custom", from: "2026-10-06", to: "2026-11-04" }));
  });

  it("shows the date inputs only for «From…to»", () => {
    renderBar({ ...emptyAnalyticsFilter(), period: "custom", from: "2026-10-01", to: "2026-10-31" });
    expect(screen.getAllByLabelText("From").length).toBeGreaterThan(0);
    expect(screen.getAllByLabelText("To").length).toBeGreaterThan(0);
    expect(document.querySelector('input[type="date"]')).toBeNull();
  });

  it("opens the filter sheet with the page's groups and toggles a chip", () => {
    const onChange = renderBar(emptyAnalyticsFilter());
    fireEvent.click(screen.getByTestId("analytics-filters-button"));
    const sheet = screen.getByTestId("analytics-filter-sheet");
    expect(within(sheet).getByText("Branch")).toBeInTheDocument();
    expect(within(sheet).getByText("Coach")).toBeInTheDocument();
    expect(within(sheet).queryByText("Class type")).not.toBeInTheDocument();
    expect(within(sheet).getAllByRole("button", { name: "Unknown" }).length).toBe(1);

    fireEvent.click(within(sheet).getByRole("button", { name: "Men" }));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ genders: ["men"] }));
    fireEvent.click(within(sheet).getByRole("button", { name: "Pagrati" }));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ location_ids: [LOCATION_B] }));
  });

  it("lists active filters as removable chips and counts them on the button", () => {
    const onChange = renderBar({ ...emptyAnalyticsFilter(), genders: ["men"], coach_ids: [COACH] });
    expect(screen.getByTestId("analytics-filters-button")).toHaveTextContent("Filters (2)");
    fireEvent.click(screen.getByRole("button", { name: "Remove Gender: Men" }));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ genders: [], coach_ids: [COACH] }));
  });
});

describe("useAnalyticsFilter", () => {
  function Probe() {
    const { filter, setFilter, apiQuery } = useAnalyticsFilter();
    return (
      <>
        <output data-testid="query">{JSON.stringify(apiQuery)}</output>
        <button type="button" onClick={() => setFilter({ ...filter, period: "7", levels: ["beginner"] })}>
          change
        </button>
      </>
    );
  }

  it("reads the filter from the URL and writes it back without scrolling", () => {
    state.search = `period=90&location_ids=${LOCATION_A}`;
    wrap(<Probe />);
    expect(JSON.parse(screen.getByTestId("query").textContent ?? "{}")).toEqual({ days: "90", location_ids: LOCATION_A });

    fireEvent.click(screen.getByRole("button", { name: "change" }));
    expect(state.replace).toHaveBeenCalledWith(`/admin/metrics/training?period=7&location_ids=${LOCATION_A}&levels=beginner`, { scroll: false });
  });
});

describe("KpiTile", () => {
  const tile = (entry: Record<string, unknown>, key = "training.no_show_rate") =>
    wrap(<KpiTile kpi={readKpi({ kpis: { [key]: entry } }, key)} />);

  it("colours the change by direction (lower is better for no-shows)", () => {
    tile({ value: 8, previous: 6, delta: 2 });
    expect(screen.getByText("8%")).toBeInTheDocument();
    expect(document.querySelector("[data-tone]")).toHaveAttribute("data-tone", "bad");
  });

  it("shows «—» with a short reason when suppressed", () => {
    tile({ value: null, suppressed: true });
    expect(screen.getByLabelText("Hidden: fewer than 5 people")).toHaveTextContent("—");
    expect(screen.getByText("Hidden: fewer than 5 people")).toBeInTheDocument();
  });

  it("shows the reset date next to the label", () => {
    tile({ value: 8, since: "2026-11-04T09:00:00Z" });
    expect(screen.getByTestId("metric-since")).toHaveTextContent("from Nov 4");
  });
});

describe("reset from the infobox", () => {
  it("confirms, resets and refetches", async () => {
    const { client } = wrap(<KpiTile kpi={readKpi({ kpis: { "training.no_show_rate": { value: 8 } } }, "training.no_show_rate")} />);
    const invalidate = vi.spyOn(client, "invalidateQueries");

    fireEvent.click(screen.getByRole("button", { name: "About: No-shows" }));
    const box = screen.getByRole("dialog", { name: "About: No-shows" });
    expect(within(box).getByText("What it measures")).toBeInTheDocument();
    expect(within(box).queryByText("A good number")).not.toBeInTheDocument();
    fireEvent.click(within(box).getByRole("button", { name: "Reset from today" }));

    expect(screen.getByText(/Old data is not deleted/)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("analytics-reset-confirm"));
    await waitFor(() => expect(state.reset).toHaveBeenCalledWith("token", "training.no_show_rate"));
    await waitFor(() => expect(invalidate).toHaveBeenCalledWith({ queryKey: ["admin", "analytics"] }));
  });

  it("is not offered without reset_analytics or for a snapshot metric", () => {
    state.membership = { capabilities: {} };
    const first = wrap(<KpiTile kpi={readKpi({ kpis: { "training.no_show_rate": { value: 8 } } }, "training.no_show_rate")} />);
    fireEvent.click(screen.getByRole("button", { name: "About: No-shows" }));
    expect(screen.queryByRole("button", { name: "Reset from today" })).not.toBeInTheDocument();
    first.unmount();

    state.membership = { capabilities: { reset_analytics: true } };
    wrap(<KpiTile kpi={readKpi({ kpis: { "overview.active_members": { value: 80 } } }, "overview.active_members")} />);
    fireEvent.click(screen.getByRole("button", { name: "About: Active box members" }));
    expect(screen.queryByRole("button", { name: "Reset from today" })).not.toBeInTheDocument();
  });
});

describe("per-widget infoboxes", () => {
  const sections: AnalyticsSection[] = ["overview", "training", "coaching", "engagement", "health"];

  it.each(sections)("gives every widget on «%s» its own help text", async (section) => {
    wrap(<AdminAnalytics section={section} />);
    await screen.findAllByTestId(/^kpi-/);
    const keys = helpKeys();
    expect(keys.length).toBeGreaterThan(3);
    expect(keys.every((key) => key.length > 10)).toBe(true);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it("renders every metric key the page gets", async () => {
    wrap(<AdminAnalytics section="training" />);
    await screen.findAllByTestId(/^kpi-/);
    for (const key of Object.keys(STAFF_METRICS).filter((key) => key.startsWith("training.") && key !== "training.execution_kpis")) {
      expect(screen.getByTestId(`kpi-${key}`)).toBeInTheDocument();
    }
    expect(screen.queryByText(/Attendance, completions, workout type/)).not.toBeInTheDocument();
  });

  it("does the same for finance analytics", async () => {
    wrap(<FinanceDashboard analyticsMode />);
    await screen.findByTestId("kpi-finance.mrr");
    const keys = helpKeys();
    expect(keys.length).toBeGreaterThan(10);
    expect(new Set(keys).size).toBe(keys.length);
    expect(state.financeSummary).toHaveBeenCalledWith("token", { days: "30" });
  });
});

describe("AnalyticsResetHistory", () => {
  it("lists resets and undoes an active one after confirming", async () => {
    state.resets.mockResolvedValue({
      page: 1,
      per_page: 20,
      total: 2,
      entries: [
        {
          id: "r1",
          metric_key: "training.no_show_rate",
          scope: "organization",
          reset_at: "2026-11-04T09:00:00Z",
          reset_by: COACH,
          undone_at: null,
          undone_by: null,
          active: true,
          before: { from: "2026-10-05", to: "2026-11-03", value: 12.5 },
        },
        {
          id: "r0",
          metric_key: "finance.arpm",
          scope: "organization",
          reset_at: "2026-10-01T09:00:00Z",
          reset_by: null,
          undone_at: "2026-10-02T09:00:00Z",
          undone_by: null,
          active: false,
          before: null,
        },
      ],
    });
    wrap(<AnalyticsResetHistory />);

    const rows = await screen.findAllByTestId("analytics-reset-row");
    expect(rows).toHaveLength(2);
    expect(within(rows[0]!).getByText("No-shows")).toBeInTheDocument();
    expect(within(rows[0]!).getByText("Maria")).toBeInTheDocument();
    expect(within(rows[0]!).getByText("12.5% · Oct 5–Nov 3")).toBeInTheDocument();
    expect(within(rows[0]!).getByText("Active")).toBeInTheDocument();
    expect(within(rows[1]!).getByText(/^Undone/)).toBeInTheDocument();
    expect(within(rows[1]!).queryByRole("button", { name: "Undo" })).not.toBeInTheDocument();

    fireEvent.click(within(rows[0]!).getByRole("button", { name: "Undo" }));
    await act(async () => {
      fireEvent.click(screen.getByTestId("analytics-undo-confirm"));
    });
    await waitFor(() => expect(state.undo).toHaveBeenCalledWith("token", "r1"));
  });

  it("says so when nothing was reset", async () => {
    state.resets.mockResolvedValue({ page: 1, per_page: 20, total: 0, entries: [] });
    wrap(<AnalyticsResetHistory />);
    expect(await screen.findByText("No figure has been reset yet.")).toBeInTheDocument();
  });
});
