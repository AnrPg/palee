import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  addStatusIncidentUpdate,
  fetchStatusConsole,
  publishStatusIncident,
  translateStatusText,
  type StatusConsole,
  type StatusIncident,
} from "@/api/service-status";
import { PlatformStatusPage } from "@/components/platform/PlatformStatusPage";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));
vi.mock("@/api/service-status", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/service-status")>()),
  fetchStatusConsole: vi.fn(),
  translateStatusText: vi.fn(),
  publishStatusIncident: vi.fn(),
  addStatusIncidentUpdate: vi.fn(),
}));

const keys = ["app", "search", "files", "email", "payments", "fiscal"];
const open: StatusIncident = {
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
  published_by: "Nikos",
  updates: [{ id: "u1", status: "investigating", body: "Το ερευνούμε.", body_en: null, locale: "el", en_source: null, created_at: "2026-11-02T19:20:00Z", published_by: "Nikos" }],
};

function console(overrides: Partial<StatusConsole> = {}): StatusConsole {
  return {
    probes: keys.map((key) => ({
      key,
      status: key === "email" ? "degraded" : "operational",
      reason: key === "email" ? "daily limit" : null,
      checked_at: "2026-11-02T19:30:00Z",
      changed_at: "2026-11-02T19:12:00Z",
    })),
    incidents: [],
    subscribers: { confirmed: 37, waiting: 2 },
    ...overrides,
  };
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PlatformStatusPage />
    </QueryClientProvider>,
  );
}

async function openForm() {
  fireEvent.click(await screen.findByRole("button", { name: "newAction" }));
  fireEvent.change(screen.getByLabelText("titleLabel"), { target: { value: "Καθυστερήσεις στα email" } });
  fireEvent.change(screen.getByLabelText("bodyLabel"), { target: { value: "Τα αποδεικτικά αργούν." } });
  fireEvent.blur(screen.getByLabelText("bodyLabel"));
}

describe("PlatformStatusPage (ADR-366, W7 screen 2)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("«Τώρα» shows the checks, says no problem was written, one primary button and a closed history", async () => {
    vi.mocked(fetchStatusConsole).mockResolvedValue(console());
    renderPage();
    const now = await screen.findByTestId("status-console-now");
    expect(now.textContent).toContain("componentStatus.degraded");
    expect(now.textContent).toContain("(daily limit)");
    expect(now.textContent).toContain("noIncidentWritten");
    expect(screen.getByTestId("status-console-badge").textContent).toContain("overall.partial_outage");
    expect((screen.getByTestId("status-console-history") as HTMLDetailsElement).open).toBe(false);
    expect(screen.getByText('subscribers:{"count":37}')).toBeTruthy();
  });

  it("an open incident shows who published it and takes a new step", async () => {
    vi.mocked(fetchStatusConsole).mockResolvedValue(console({ incidents: [open] }));
    vi.mocked(translateStatusText).mockResolvedValue({ locale: "el", title: null, body: "Fixed." });
    vi.mocked(addStatusIncidentUpdate).mockResolvedValue({ ...open, status: "resolved" });
    renderPage();
    expect((await screen.findByTestId("status-console-open")).textContent).toContain('publishedBy:{"name":"Nikos"}');
    fireEvent.click(screen.getByRole("button", { name: "updateAction" }));
    fireEvent.click(screen.getByRole("radio", { name: "incidentStatus.resolved" }));
    fireEvent.change(screen.getByLabelText("bodyLabel"), { target: { value: "Διορθώθηκε." } });
    fireEvent.blur(screen.getByLabelText("bodyLabel"));
    await screen.findByTestId("status-english-preview");
    fireEvent.click(screen.getByRole("button", { name: "publishUpdate" }));
    await waitFor(() =>
      expect(addStatusIncidentUpdate).toHaveBeenCalledWith("token", "i1", {
        status: "resolved",
        body: "Διορθώθηκε.",
        notify: true,
        locale: "el",
        body_en: "Fixed.",
        en_source: "auto",
      }),
    );
  });

  it("previews the English translation, lets the publisher correct it, and sends it as edited", async () => {
    vi.mocked(fetchStatusConsole).mockResolvedValue(console());
    vi.mocked(translateStatusText).mockResolvedValue({ locale: "el", title: "Email delays", body: "Receipts are late." });
    vi.mocked(publishStatusIncident).mockResolvedValue(open);
    renderPage();
    await openForm();

    const preview = await screen.findByTestId("status-english-preview");
    expect(preview.textContent).toContain("machineTranslation");
    expect(preview.textContent).toContain("Receipts are late.");
    expect(translateStatusText).toHaveBeenCalledWith("token", { title: "Καθυστερήσεις στα email", body: "Τα αποδεικτικά αργούν." });

    fireEvent.click(screen.getByRole("button", { name: "correct" }));
    fireEvent.change(screen.getByLabelText("englishBody"), { target: { value: "Receipts are delayed." } });
    fireEvent.click(screen.getByRole("button", { name: "publish" }));

    await waitFor(() =>
      expect(publishStatusIncident).toHaveBeenCalledWith(
        "token",
        expect.objectContaining({ locale: "el", title_en: "Email delays", body_en: "Receipts are delayed.", en_source: "edited", impact: "minor" }),
      ),
    );
  });

  it("publishes untranslated when the translation fails", async () => {
    vi.mocked(fetchStatusConsole).mockResolvedValue(console());
    vi.mocked(translateStatusText).mockRejectedValue(new ApiError(503, "no", { code: "status_translation_unavailable" }));
    vi.mocked(publishStatusIncident).mockResolvedValue(open);
    renderPage();
    await openForm();

    expect(await screen.findByTestId("status-translation-failed")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "publish" }));
    await waitFor(() => expect(publishStatusIncident).toHaveBeenCalled());
    expect(vi.mocked(publishStatusIncident).mock.calls[0][1]).not.toHaveProperty("title_en");
  });

  it("keeps errors inside the form: the wrong field turns red with a reason", async () => {
    vi.mocked(fetchStatusConsole).mockResolvedValue(console());
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "newAction" }));
    fireEvent.change(screen.getByLabelText("titleLabel"), { target: { value: "ab" } });
    fireEvent.click(screen.getByRole("button", { name: "publish" }));
    expect(await screen.findByText("errorTitle")).toBeTruthy();
    expect(screen.getByLabelText("titleLabel").getAttribute("aria-invalid")).toBe("true");
    expect(screen.getByText("errorBody")).toBeTruthy();
    expect(publishStatusIncident).not.toHaveBeenCalled();
  });
});
