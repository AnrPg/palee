import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { PublicSiteV2, SiteTemplateKey } from "@/api/box-site";
import { publicPackagesKey } from "@/api/my-payments";

import el from "../../../../messages/el.json";

import { BoxWebsite } from "./BoxWebsite";
import type { SitePage } from "./site-model";
import { BASIC, boxPage, boxSite, NOW, PACKAGES } from "./site.test-fixtures";

const api = vi.hoisted(() => ({ sendSiteForm: vi.fn(async () => ({})) }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/api/my-payments", async (original) => ({
  ...(await original<typeof import("@/api/my-payments")>()),
  fetchPublicPackages: vi.fn(async () => ({ packages: PACKAGES, online_payments: false })),
}));
const router = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => router, usePathname: () => "/b/box-kypseli", useSearchParams: () => new URLSearchParams() }));

const TEMPLATES: SiteTemplateKey[] = ["arena", "tiles", "stories", "atelier"];
const ALL_PAGES = ["Αρχική", "Πρόγραμμα", "Πακέτα", "Coaches", "Ο χώρος"];

function show({
  template = "arena",
  site: over = {},
  pageKey = "home",
  preview,
}: {
  template?: SiteTemplateKey;
  site?: Partial<PublicSiteV2>;
  pageKey?: SitePage;
  preview?: { device: "phone" | "desk"; onNavigate: (page: SitePage) => void };
} = {}) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: Infinity } } });
  queries.setQueryData(publicPackagesKey("box-kypseli"), { packages: PACKAGES, online_payments: false });
  return render(
    <QueryClientProvider client={queries}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <BoxWebsite page={boxPage()} site={boxSite({ template, ...over })} language="box" basePath="/b/box-kypseli" standalone={false} pageKey={pageKey} preview={preview} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

/** The menu's page names (the «Ατελιέ» menu is a layer behind its button). */
function menuPages(template: SiteTemplateKey) {
  if (template === "atelier") fireEvent.click(screen.getByTestId("site-menu-open"));
  const navs = screen.queryAllByRole("navigation", { name: "Σελίδες" });
  if (navs.length === 0) return [];
  return within(navs.at(-1)!)
    .getAllByRole("link")
    .map((link) => link.textContent?.replace(/^\P{L}+/u, "").trim());
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  window.scrollTo = vi.fn() as never;
});
afterEach(() => {
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe.each(TEMPLATES)("BoxWebsite «%s»", (template) => {
  it("shows every section with data and every page in the menu", () => {
    show({ template });
    const root = screen.getByTestId("box-website");
    expect(root).toHaveAttribute("data-template", template);
    expect(root).toHaveAttribute("lang", "el");
    expect(root.className).not.toContain("calm");
    expect(screen.getByTestId("site-hero")).toBeInTheDocument();
    expect(screen.getAllByTestId(/site-(wod|coaches|stats|stories|bento)/).length).toBeGreaterThan(0);
    expect(menuPages(template)).toEqual(ALL_PAGES);
  });

  it("with the basic set leaves out empty pages and their sections", () => {
    show({ template, site: { sections: BASIC } });
    expect(screen.queryByTestId("site-wod")).toBeNull();
    expect(screen.queryByTestId("site-coaches")).toBeNull();
    expect(screen.queryByTestId("site-stats")).toBeNull();
    expect(screen.queryByTestId("site-next-class")).toBeNull();
    expect(menuPages(template)).toEqual(["Αρχική", "Πακέτα", "Ο χώρος"]);
  });

  it("renders each sub-page", () => {
    const { unmount } = show({ template, pageKey: "schedule" });
    expect(screen.getByTestId("box-website")).toHaveAttribute("data-page", "schedule");
    expect(screen.getByTestId("site-schedule")).toBeInTheDocument();
    unmount();
    show({ template, pageKey: "coaches" });
    expect(screen.getAllByText("Μαρία").length).toBeGreaterThan(0);
  });

  it("moves less with «Λιγότερη κίνηση»", () => {
    show({ template, site: { calm_motion: true } });
    expect(screen.getByTestId("box-website").className).toContain("calm");
  });

  it("switches pages through the preview's callback", () => {
    const onNavigate = vi.fn();
    show({ template, preview: { device: "phone", onNavigate } });
    expect(screen.getByTestId("box-website-preview")).toHaveAttribute("data-device", "phone");
    if (template === "atelier") fireEvent.click(screen.getByTestId("site-menu-open"));
    const nav = screen.getAllByRole("navigation", { name: "Σελίδες" }).at(-1)!;
    fireEvent.click(within(nav).getByRole("link", { name: /Πακέτα/ }));
    expect(onNavigate).toHaveBeenCalledWith("packages");
    expect(router.push).not.toHaveBeenCalled();
  });
});

describe("BoxWebsite forms and data", () => {
  it("checks the form in the preview and sends nothing", async () => {
    show({ preview: { device: "desk", onNavigate: vi.fn() } });
    fireEvent.click(screen.getAllByTestId("site-cta")[0]!);
    const dialog = screen.getByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Όνομα"), { target: { value: "Άννα" } });
    fireEvent.change(within(dialog).getByLabelText("Κινητό ή email"), { target: { value: "anna@example.com" } });
    fireEvent.click(within(dialog).getByRole("checkbox", { name: /πολιτική απορρήτου/ }));
    await act(async () => {
      fireEvent.click(within(dialog).getByTestId("site-form-send"));
    });
    expect(screen.getByText("Ευχαριστούμε, Άννα!")).toBeInTheDocument();
    expect(screen.getByText("Προεπισκόπηση: η φόρμα δεν στάλθηκε πραγματικά.")).toBeInTheDocument();
    expect(api.sendSiteForm).not.toHaveBeenCalled();
  });

  it("puts a class from the timetable into the trial form", () => {
    show({ pageKey: "schedule" });
    fireEvent.click(screen.getAllByRole("button", { name: /^Δοκίμασε CrossFit/ })[0]!);
    expect(within(screen.getByRole("dialog")).getByText(/Επιλογή: .*17:00 · CrossFit/)).toBeInTheDocument();
  });

  it("counts down to the next class in the box's time zone", () => {
    show();
    const next = screen.getByTestId("site-next-class");
    expect(next.textContent).toContain("CrossFit");
    expect(next.textContent).toContain("σήμερα 17:00");
    expect(next.textContent).toContain("07:00:00");
  });

  it("uses a forced dark mode inline and «Αυτόματο» in CSS", () => {
    const { unmount } = show({ site: { appearance: "dark" } });
    expect(screen.getByTestId("box-website").getAttribute("style")).toContain("--s-bg");
    expect(document.querySelector("[data-bw] style")).toBeNull();
    unmount();
    show();
    expect(screen.getByTestId("box-website").getAttribute("style")).toBeNull();
    expect(document.querySelector("[data-bw] style")?.textContent).toContain("prefers-color-scheme: dark");
  });

  it("closes a layer with Esc", () => {
    show({ template: "arena" });
    fireEvent.click(screen.getByTestId("site-menu-open"));
    const menu = screen.getByTestId("site-menu");
    fireEvent.keyDown(menu, { key: "Escape" });
    expect(screen.queryByTestId("site-menu")).toBeNull();
  });
});
