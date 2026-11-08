import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const DRAFT_FIELDS = ["template", "palette", "appearance", "calm_motion", "hidden_sections", "public_schedule", "public_wod"];

const api = vi.hoisted(() => ({
  getSite: vi.fn(),
  getSiteSummary: vi.fn(),
  saveSite: vi.fn(),
  publishSite: vi.fn(),
  discardSiteDraft: vi.fn(),
  dismissSiteNotice: vi.fn(),
  fetchSitePreview: vi.fn(),
}));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/api/social", async (original) => ({ ...(await original<object>()), fetchPublicBox: () => new Promise(() => {}) }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "kypseli", adminHref: (path: string) => path }));

import { WebsiteSettings } from "./WebsiteSettings";

type Settings = Record<string, unknown> & { draft: Record<string, unknown> | null; lock_version: number };

let server: Settings;

function settings(extra: Partial<Settings> = {}): Settings {
  return {
    banner_version: 1,
    conversions_api_enabled: false,
    faq: [],
    forms_enabled: true,
    ga4_measurement_id: null,
    gtm_container_id: null,
    has_conversions_api_token: false,
    hidden_sections: [],
    lock_version: 3,
    meta_pixel_id: null,
    public_schedule: true,
    public_wod: false,
    section_order: ["hero", "about"],
    translation_locales: [],
    visible_locales: [],
    template: "arena",
    palette: "palee",
    appearance: "auto",
    calm_motion: false,
    draft: null,
    published_at: null,
    template_notice: false,
    ...extra,
  };
}

const languages = { source: "el", available: ["en"], machine_available: false, progress: [] };

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <WebsiteSettings />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  server = settings();
  for (const mock of Object.values(api)) mock.mockReset();
  api.getSite.mockImplementation(async () => ({ settings: server, domains: [], languages }));
  api.getSiteSummary.mockReturnValue(new Promise(() => {}));
  api.fetchSitePreview.mockReturnValue(new Promise(() => {}));
  // The API keeps the publishable fields as a draft (ADR-530 §2).
  api.saveSite.mockImplementation(async (_token: string, body: Record<string, unknown>) => {
    const draft = { ...(server.draft ?? {}) };
    const rest: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(body)) (DRAFT_FIELDS.includes(key) ? draft : rest)[key] = value;
    server = { ...server, ...rest, draft, lock_version: server.lock_version + 1 };
    return { settings: server, languages };
  });
  api.publishSite.mockImplementation(async () => {
    server = { ...server, ...(server.draft ?? {}), draft: null, template_notice: false };
    return { settings: server };
  });
  api.discardSiteDraft.mockImplementation(async () => {
    server = { ...server, draft: null };
    return { settings: server };
  });
  api.dismissSiteNotice.mockImplementation(async () => {
    server = { ...server, template_notice: false };
    return { settings: server };
  });
});

describe("WebsiteSettings (ADR-530)", () => {
  it("shows the four templates, the twelve palettes with the contrast note and the groups of switches, without order arrows", async () => {
    renderPage();
    const look = await screen.findByTestId("website-look");
    const templates = within(look).getByRole("radiogroup", { name: "Template" });
    expect(within(templates).getAllByRole("radio").map((radio) => radio.textContent)).toEqual([
      expect.stringContaining("Αρένα"),
      expect.stringContaining("Πλακίδια"),
      expect.stringContaining("Ιστορίες"),
      expect.stringContaining("Ατελιέ"),
    ]);
    expect(within(templates).getByRole("radio", { name: /Αρένα/ }).getAttribute("aria-checked")).toBe("true");
    const colours = within(look).getByRole("radiogroup", { name: "Χρώματα" });
    expect(within(colours).getAllByRole("radio")).toHaveLength(12);
    expect(within(colours).getByRole("radio", { name: "Μονόχρωμο" })).toBeTruthy();
    expect(screen.getByTestId("website-contrast").textContent).toContain("AA ✓");

    const sections = screen.getByTestId("website-sections");
    expect(within(sections).getByRole("group", { name: "Ομάδα και χώρος" })).toBeTruthy();
    expect(within(sections).getByRole("switch", { name: "Ωρολόγιο" }).getAttribute("aria-checked")).toBe("true");
    expect(within(sections).getByRole("switch", { name: "WOD της ημέρας" }).getAttribute("aria-checked")).toBe("false");
    expect(within(screen.getByTestId("website-section-photos")).getByText("νέο")).toBeTruthy();
    expect(within(sections).queryByRole("button", { name: /Μετακίνηση/ })).toBeNull();
    expect(screen.getByTestId("website-publish-status").textContent).toBe("Όλα δημοσιευμένα.");
  });

  it("moves through the templates with the arrow keys and saves each choice as a draft", async () => {
    renderPage();
    const arena = await screen.findByRole("radio", { name: /Αρένα/ });
    fireEvent.keyDown(arena, { key: "ArrowRight" });
    await waitFor(() => expect(api.saveSite).toHaveBeenCalledWith("token", { lock_version: 3, template: "tiles" }));
    expect(screen.getByRole("radio", { name: /Πλακίδια/ }).getAttribute("aria-checked")).toBe("true");
    expect(await screen.findByText("Αλλαγές που δεν δημοσιεύτηκαν: template.")).toBeTruthy();
  });

  it("«Μόνο τα βασικά» keeps about, packages, location and the trial form", async () => {
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "Μόνο τα βασικά" }));
    await waitFor(() => expect(api.saveSite).toHaveBeenCalledTimes(1));
    const body = api.saveSite.mock.calls[0]![1] as { hidden_sections: string[]; public_schedule: boolean; public_wod: boolean };
    expect(body.public_schedule).toBe(false);
    expect(body.public_wod).toBe(false);
    expect(body.hidden_sections).not.toContain("about");
    expect(body.hidden_sections).not.toContain("trial_form");
    expect(body.hidden_sections).toEqual(expect.arrayContaining(["photos", "stats", "events", "coaches", "faq", "contact_form"]));
    const sections = screen.getByTestId("website-sections");
    // ADR-553: «Πακέτα» is no switch here; it follows «Ποιος βλέπει τα πακέτα συνδρομής».
    expect(within(sections).queryByRole("switch", { name: "Πακέτα" })).toBeNull();
    expect(within(sections).getByTestId("website-packages-audience")).toHaveTextContent("Ποιος βλέπει τα πακέτα");
    expect(within(sections).getByRole("switch", { name: "Coaches" }).getAttribute("aria-checked")).toBe("false");
    expect(await screen.findByText("Αλλαγές που δεν δημοσιεύτηκαν: ενότητες.")).toBeTruthy();
  });

  it("lists what changed, publishes the draft and says when visitors see it", async () => {
    renderPage();
    fireEvent.click(await screen.findByRole("radio", { name: "Φλόγα" }));
    await waitFor(() => expect(api.saveSite).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole("switch", { name: "Λιγότερη κίνηση" }));
    expect(await screen.findByText("Αλλαγές που δεν δημοσιεύτηκαν: χρώματα, κίνηση.")).toBeTruthy();
    await waitFor(() => expect(api.saveSite).toHaveBeenCalledTimes(2));
    expect(api.saveSite.mock.calls[1]![1]).toEqual({ lock_version: 4, calm_motion: true });

    const publish = screen.getByRole("button", { name: "Δημοσίευση" });
    await waitFor(() => expect(publish.hasAttribute("disabled")).toBe(false));
    fireEvent.click(publish);
    expect(await screen.findByText("Δημοσιεύτηκε. Οι επισκέπτες τη βλέπουν σε λίγα δευτερόλεπτα.")).toBeTruthy();
    expect(api.publishSite).toHaveBeenCalledWith("token");
    expect(screen.getByRole("radio", { name: "Φλόγα" }).getAttribute("aria-checked")).toBe("true");
  });

  it("asks before discarding more than one change", async () => {
    server = settings({ draft: { palette: "olive", template: "atelier" } });
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "Απόρριψη" }));
    const dialog = await screen.findByTestId("website-discard-confirm");
    expect(dialog.textContent).toContain("template, χρώματα");
    await act(async () => fireEvent.click(within(dialog).getByTestId("website-discard-yes")));
    await waitFor(() => expect(api.discardSiteDraft).toHaveBeenCalledWith("token"));
    expect(await screen.findByText("Όλα δημοσιευμένα.")).toBeTruthy();
  });

  it("shows the new-look notice until the owner closes it", async () => {
    server = settings({ template_notice: true });
    renderPage();
    const notice = await screen.findByTestId("website-notice");
    expect(notice.textContent).toContain("Η ιστοσελίδα σου πήρε νέα όψη: Αρένα.");
    fireEvent.click(within(notice).getByRole("button", { name: "Κλείσιμο ειδοποίησης" }));
    await waitFor(() => expect(screen.queryByTestId("website-notice")).toBeNull());
    expect(api.dismissSiteNotice).toHaveBeenCalledWith("token");
  });
});
