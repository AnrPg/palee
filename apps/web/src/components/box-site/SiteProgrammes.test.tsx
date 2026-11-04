import { render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import type { PublicSite } from "@/api/box-site";

import el from "../../../messages/el.json";

import { showsSiteProgrammes, SiteProgrammesNavLink, SiteProgrammesSection, siteProgrammes } from "./SiteProgrammes";

const card = (id: string, title: string, extra: Record<string, unknown> = {}) => ({
  id,
  title,
  price_cents: 3900,
  currency: "EUR",
  weeks: 6,
  sessions_per_week: 4,
  level: "intermediate",
  goal: "strength",
  reviews: { average: 4.8, count: 23 },
  ...extra,
});

const site = (programmes: unknown, sections: string[] = ["hero", "programmes"]) => ({ slug: "akropoli", sections, programmes }) as unknown as PublicSite;

function wrap(node: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      {node}
    </NextIntlClientProvider>,
  );
}

// Board 4κ/4μ A, ADR-543: up to three cards and «Όλα τα προγράμματα (N)»; hidden without one on sale.
describe("SiteProgrammes", () => {
  it("reads up to three cards and the total, and nothing from a malformed payload", () => {
    const many = { items: [card("a", "A"), card("b", "B"), card("c", "C"), card("d", "D")], total: 5 };
    expect(siteProgrammes(site(many)).items.map((item) => item.id)).toEqual(["a", "b", "c"]);
    expect(siteProgrammes(site(many)).total).toBe(5);
    expect(siteProgrammes(site(undefined))).toEqual({ items: [], total: 0 });
    expect(siteProgrammes(site({ items: "x", total: "y" }))).toEqual({ items: [], total: 0 });
    expect(siteProgrammes(site({ items: [null, { title: "no id" }, card("a", "A")] }))).toMatchObject({ total: 1 });
    expect(showsSiteProgrammes(site(many))).toBe(true);
    expect(showsSiteProgrammes(site(many, ["hero"]))).toBe(false);
    expect(showsSiteProgrammes(site({ items: [], total: 0 }))).toBe(false);
  });

  it("shows the cards with their facts, price and link, and «Όλα τα προγράμματα (N)»", () => {
    wrap(<SiteProgrammesSection site={site({ items: [card("a", "Δύναμη σε 6 εβδομάδες"), card("b", "Τρέξιμο 10K", { reviews: { average: null, count: 0 }, level: "beginner", cover_url: "https://media.example/c.webp" })], total: 5 })} />);
    const section = screen.getByTestId("site-programmes");
    expect(within(section).getByText("Προγράμματα για όπου κι αν είσαι")).toBeTruthy();
    const first = screen.getByTestId("site-programme-a");
    expect(within(first).getByText("6 εβδ. · 4 την εβδ. · Μεσαίοι · ★ 4,8 (23)")).toBeTruthy();
    expect(within(first).getByText("39,00 €")).toBeTruthy();
    expect(within(first).getByRole("link", { name: "Δες το" }).getAttribute("href")).toBe("/b/akropoli/programmes/a");
    const second = screen.getByTestId("site-programme-b");
    expect(within(second).getByText("6 εβδ. · 4 την εβδ. · Αρχάριοι · Νέο")).toBeTruthy();
    expect(second.querySelector("img")?.getAttribute("src")).toBe("https://media.example/c.webp");
    expect(screen.getByTestId("site-programmes-all").textContent).toBe("Όλα τα προγράμματα προπόνησης (5)");
    expect(screen.getByTestId("site-programmes-all").getAttribute("href")).toBe("/b/akropoli/programmes");
  });

  it("leaves out «Όλα» when every programme shows, and the whole section without one", () => {
    const { unmount } = wrap(<SiteProgrammesSection site={site({ items: [card("a", "A")], total: 1 })} />);
    expect(screen.queryByTestId("site-programmes-all")).toBeNull();
    unmount();
    wrap(<SiteProgrammesSection site={site({})} />);
    expect(screen.queryByTestId("site-programmes")).toBeNull();
  });

  it("puts «Προγράμματα» in the site menu only when the section shows", () => {
    const { unmount } = wrap(<SiteProgrammesNavLink site={site({ items: [card("a", "A")], total: 1 })} />);
    expect(screen.getByRole("link", { name: "Προγράμματα προπόνησης" }).getAttribute("href")).toBe("#site-programmes");
    unmount();
    wrap(<SiteProgrammesNavLink site={null} />);
    expect(screen.queryByRole("link")).toBeNull();
  });
});
