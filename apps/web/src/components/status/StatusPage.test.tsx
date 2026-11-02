import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  confirmStatusSubscription,
  fetchStatusHistory,
  fetchStatusOverview,
  subscribeToStatus,
  type StatusHistory,
  type StatusIncident,
  type StatusOverview,
} from "@/api/service-status";
import { StatusPage } from "@/components/status/StatusPage";

let search = new URLSearchParams();
let wide = true;

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
  useSearchParams: () => search,
}));
vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/api/service-status", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/service-status")>()),
  fetchStatusOverview: vi.fn(),
  fetchStatusHistory: vi.fn(),
  subscribeToStatus: vi.fn(),
  confirmStatusSubscription: vi.fn(),
  unsubscribeFromStatus: vi.fn(),
}));

const incident: StatusIncident = {
  id: "i1",
  kind: "incident",
  title: "Καθυστερήσεις στα email",
  title_en: "Email delays",
  locale: "el",
  en_source: "auto",
  impact: "minor",
  status: "investigating",
  components: ["email"],
  scheduled_for: null,
  scheduled_until: null,
  started_at: "2026-11-02T19:12:00Z",
  resolved_at: null,
  updates: [
    {
      id: "u1",
      status: "investigating",
      body: "Τα αποδεικτικά φεύγουν με καθυστέρηση.",
      body_en: "Receipts are delayed.",
      locale: "el",
      en_source: "auto",
      created_at: "2026-11-02T19:20:00Z",
    },
  ],
};

const keys = ["app", "search", "files", "email", "payments", "fiscal"] as const;
const overview: StatusOverview = {
  status: "partial_outage",
  components: keys.map((key) => ({ key, status: key === "email" ? "degraded" : "operational", checked_at: "2026-11-02T19:30:00Z" })),
  active: [incident],
  upcoming: [],
  generated_at: "2026-11-02T19:30:00Z",
};

const history: StatusHistory = {
  days: 90,
  from: "2026-08-05",
  to: "2026-11-02",
  generated_at: "2026-11-02T19:30:00Z",
  components: keys.map((key) => ({
    key,
    uptime_percent: 100,
    days: Array.from({ length: 90 }, (_, i) => ({
      date: new Date(Date.UTC(2026, 7, 5 + i)).toISOString().slice(0, 10),
      status: key === "email" && i === 89 ? "degraded" : "operational",
      uptime_percent: key === "email" && i === 89 ? 40 : 100,
    })),
  })),
  incidents: [
    { ...incident, id: "old", title: "Πληρωμές με κάρτα: αργές απαντήσεις", started_at: "2026-10-12T10:00:00Z", resolved_at: "2026-10-12T10:35:00Z", status: "resolved" },
  ],
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <StatusPage />
    </QueryClientProvider>,
  );
}

describe("StatusPage (ADR-364/366, W7 screen 1)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    search = new URLSearchParams();
    wide = true;
    window.matchMedia = vi.fn().mockImplementation(() => ({
      matches: wide,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })) as unknown as typeof window.matchMedia;
    vi.mocked(fetchStatusOverview).mockResolvedValue(overview);
    vi.mocked(fetchStatusHistory).mockResolvedValue(history);
  });

  it("shows the current incident in the reader's language with its latest step", async () => {
    renderPage();
    const card = await screen.findByTestId("status-incident");
    expect(card.textContent).toContain("Καθυστερήσεις στα email");
    expect(card.textContent).toContain("incidentStatus.investigating");
    expect(card.textContent).toContain("Τα αποδεικτικά φεύγουν με καθυστέρηση.");
    expect(card.textContent).toContain("othersFine");
    expect(card.textContent).not.toContain("machineTranslation");
  });

  it("shows 90 days per component on a desktop and 30 on a phone", async () => {
    renderPage();
    const email = await screen.findByTestId("status-component-email");
    expect(email.querySelectorAll("[role=img] > span")).toHaveLength(90);
    expect(email.textContent).toContain("componentStatus.degraded");
  });

  it("shows 30 days on a phone", async () => {
    wide = false;
    renderPage();
    const app = await screen.findByTestId("status-component-app");
    expect(app.querySelectorAll("[role=img] > span")).toHaveLength(30);
    expect(screen.getByTestId("status-components").dataset.days).toBe("30");
  });

  it("lists earlier incidents with how long they lasted", async () => {
    renderPage();
    const past = await screen.findByTestId("status-past");
    expect(past.textContent).toContain("Πληρωμές με κάρτα: αργές απαντήσεις");
    expect(past.textContent).toContain('minutes:{"count":35}');
    expect(past.textContent).toContain("resolvedWord");
  });

  it("signs up with double opt-in; a wrong address turns the field red with a reason", async () => {
    vi.mocked(subscribeToStatus).mockResolvedValue({ status: "accepted" });
    renderPage();
    const input = await screen.findByLabelText("emailLabel");
    fireEvent.change(input, { target: { value: "not-an-email" } });
    fireEvent.click(screen.getByRole("button", { name: "subscribe" }));
    expect(await screen.findByText("emailInvalid")).toBeTruthy();
    expect(input.getAttribute("aria-invalid")).toBe("true");
    expect(subscribeToStatus).not.toHaveBeenCalled();

    fireEvent.change(input, { target: { value: "maria@example.com" } });
    fireEvent.click(screen.getByRole("button", { name: "subscribe" }));
    await waitFor(() => expect(subscribeToStatus).toHaveBeenCalledWith("maria@example.com", "el"));
    expect(await screen.findByText('subscribed:{"email":"maria@example.com"}')).toBeTruthy();
  });

  it("confirms the email link and says when it expired", async () => {
    search = new URLSearchParams("confirm=abc");
    vi.mocked(confirmStatusSubscription).mockRejectedValue(new ApiError(404, "gone", { code: "status_subscription_not_found" }));
    renderPage();
    expect((await screen.findByTestId("status-link-result")).textContent).toBe("link.expired");
    expect(confirmStatusSubscription).toHaveBeenCalledWith("abc");
  });
});
