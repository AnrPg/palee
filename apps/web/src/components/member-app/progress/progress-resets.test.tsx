import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ACCOUNT_PROGRESS_KEY } from "@/api/account-training";
import en from "../../../../messages/en.json";

import { baselineOf, MetricTitleAside } from "./MetricInfo";
import { ProgressResetHistory } from "./ProgressResetHistory";
import { sinceBaseline } from "@/components/client/consistency";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

function renderWith(node: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        {node}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return client;
}

/** A stand-in Πρόοδος card: it reads `/me/progress` and shows its weekly «?». */
function WeeklyCard() {
  const query = useQuery({
    queryKey: [...ACCOUNT_PROGRESS_KEY],
    queryFn: () => apiRequest("/me/progress") as Promise<{ metric_baselines?: Record<string, string> }>,
  });
  if (!query.data) return null;
  return (
    <div data-testid="card">
      <h2>Weekly volume</h2>
      <MetricTitleAside
        metricKey="progress.weekly"
        title="Weekly volume"
        since={baselineOf(query.data.metric_baselines, "progress.weekly")}
      />
    </div>
  );
}

const reset = {
  id: "r-1",
  metric_key: "progress.weekly",
  reset_at: "2026-11-04T08:00:00Z",
  reset_by: "u-1",
  scope: "member",
  undone_at: null,
  undone_by: null,
};

describe("member reset of a Πρόοδος stat (ADR-462 §5)", () => {
  beforeEach(() => {
    apiRequest.mockReset();
  });

  it("explains the widget, asks first, POSTs the reset and shows «since» after the refetch", async () => {
    let baselines: Record<string, string> | undefined;
    apiRequest.mockImplementation(async (path: string, options?: { method?: string }) => {
      if (path === "/me/progress") return baselines ? { metric_baselines: baselines } : {};
      if (path.endsWith("/reset") && options?.method === "POST") {
        baselines = { "progress.weekly": reset.reset_at };
        return { reset };
      }
      throw new Error(`unexpected ${path}`);
    });
    renderWith(<WeeklyCard />);

    // A stub without metric_baselines: no badge.
    const card = await screen.findByTestId("card");
    expect(within(card).queryByTestId("metric-since")).toBeNull();

    fireEvent.click(within(card).getByRole("button", { name: /Weekly volume/ }));
    const info = await screen.findByRole("dialog");
    expect(info).toHaveTextContent(en.ProgressResets.info.weekly.what);
    expect(info).toHaveTextContent(en.ProgressResets.info.weekly.how);
    expect(info).toHaveTextContent(en.ProgressResets.info.weekly.change);

    fireEvent.click(within(info).getByRole("button", { name: en.ProgressResets.reset }));
    const confirm = await screen.findByRole("dialog");
    expect(confirm).toHaveTextContent(en.ProgressResets.confirmBody);
    expect(apiRequest).not.toHaveBeenCalledWith(expect.stringContaining("/reset"), expect.anything());

    fireEvent.click(within(confirm).getByRole("button", { name: en.ProgressResets.confirm }));
    await waitFor(() =>
      expect(apiRequest).toHaveBeenCalledWith(
        "/me/progress/metrics/progress.weekly/reset",
        expect.objectContaining({ method: "POST", token: "token", scope: "account" }),
      ),
    );
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(await within(card).findByTestId("metric-since")).toHaveTextContent("since Nov 4");
  });

  it("cancelling the confirm sends nothing", async () => {
    apiRequest.mockResolvedValue({});
    renderWith(<WeeklyCard />);
    fireEvent.click(await screen.findByRole("button", { name: /Weekly volume/ }));
    fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: en.ProgressResets.reset }));
    fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: en.ProgressResets.cancel }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("ignores a missing or broken baseline", () => {
    expect(baselineOf(undefined, "progress.totals")).toBeNull();
    expect(baselineOf({ "progress.totals": "nope" }, "progress.totals")).toBeNull();
    expect(baselineOf({ "progress.totals": reset.reset_at }, "progress.totals")?.toISOString()).toBe(
      "2026-11-04T08:00:00.000Z",
    );
  });

  it("Συνέπεια counts only from the reset day on", () => {
    const weekly = [
      { week_start: "2026-10-19", sessions: 3 },
      { week_start: "2026-10-26", sessions: 4 },
      { week_start: "2026-11-02", sessions: 2 },
    ];
    const days = [
      { date: "2026-10-27", sessions: 4 },
      { date: "2026-11-02", sessions: 1 },
      { date: "2026-11-04", sessions: 1 },
    ];
    const kept = sinceBaseline(weekly, days, "2026-11-04");
    expect(kept.weekly).toEqual([{ week_start: "2026-11-02", sessions: 1 }]);
    expect(kept.days).toEqual([{ date: "2026-11-04", sessions: 1 }]);
    expect(sinceBaseline(weekly, days, null).weekly).toBe(weekly);
  });
});

describe("Ιστορικό μηδενισμών (ADR-462 §5)", () => {
  beforeEach(() => {
    apiRequest.mockReset();
  });

  const history = (active: boolean) => ({
    entries: [
      {
        ...reset,
        metric_key: "progress.depth.load",
        active,
        before: { value: 12 },
        undone_at: active ? null : "2026-11-04T09:00:00Z",
      },
      {
        ...reset,
        id: "r-0",
        metric_key: "progress.totals",
        reset_at: "2026-10-01T08:00:00Z",
        active: false,
        before: null,
        undone_at: "2026-10-02T08:00:00Z",
      },
    ],
    page: 1,
    per_page: 50,
    total: 2,
  });

  it("lists the resets, newest first, and shows an empty state without any", async () => {
    apiRequest.mockResolvedValue({ entries: [], page: 1, per_page: 50, total: 0 });
    renderWith(<ProgressResetHistory />);
    expect(await screen.findByText(en.ProgressResets.history.empty, { exact: false })).toBeInTheDocument();
    expect(apiRequest).toHaveBeenCalledWith(
      "/me/progress/resets?page=1&per_page=50",
      expect.objectContaining({ token: "token", scope: "account" }),
    );
  });

  it("shows metric, date, state and the value before, and undoes after a confirm", async () => {
    let active = true;
    apiRequest.mockImplementation(async (path: string, options?: { method?: string }) => {
      if (path.startsWith("/me/progress/resets?")) return history(active);
      if (path === "/me/progress/resets/r-1/undo" && options?.method === "POST") {
        active = false;
        return { reset: { ...reset, undone_at: "2026-11-04T09:00:00Z" } };
      }
      throw new Error(`unexpected ${path}`);
    });
    renderWith(<ProgressResetHistory />);

    const list = await screen.findByTestId("progress-reset-history");
    const rows = within(list).getAllByRole("listitem");
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent(en.ProgressResets.metric.depthLoad);
    expect(rows[0]).toHaveTextContent(en.ProgressResets.history.active);
    expect(rows[0]).toHaveTextContent("12");
    expect(rows[1]).toHaveTextContent(en.ProgressResets.metric.totals);
    expect(within(rows[1]).queryByRole("button")).toBeNull();

    fireEvent.click(within(rows[0]).getByRole("button", { name: en.ProgressResets.history.undo }));
    const dialog = await screen.findByRole("dialog");
    expect(apiRequest).not.toHaveBeenCalledWith(expect.stringContaining("/undo"), expect.anything());
    fireEvent.click(within(dialog).getByRole("button", { name: en.ProgressResets.history.undo }));

    await waitFor(() =>
      expect(apiRequest).toHaveBeenCalledWith(
        "/me/progress/resets/r-1/undo",
        expect.objectContaining({ method: "POST", token: "token", scope: "account" }),
      ),
    );
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    await waitFor(() =>
      expect(within(screen.getByTestId("progress-reset-history")).queryByRole("button", { name: en.ProgressResets.history.undo })).toBeNull(),
    );
  });
});
