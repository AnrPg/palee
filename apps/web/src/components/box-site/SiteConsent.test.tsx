import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { PublicSite } from "@/api/box-site";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ recordSiteConsent: vi.fn(async () => ({})) }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));

import { SiteConsentProvider } from "./SiteConsent";

const SITE = {
  tracking: {
    consent_required: true,
    banner_version: 1,
    validity_days: 180,
    categories: ["necessary", "analytics", "marketing"],
    tags: { ga4_measurement_id: null, gtm_container_id: null, meta_pixel_id: null },
  },
} as unknown as PublicSite;

function wrap(site = SITE) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      <SiteConsentProvider slug="kypseli" site={site}>
        <p>σελίδα</p>
      </SiteConsentProvider>
    </NextIntlClientProvider>,
  );
}

// ANR s4 A: a bottom bar with three equal buttons; nothing loads before a choice.
describe("SiteConsentProvider", () => {
  afterEach(() => {
    document.cookie = "palee_site_consent_kypseli=; Max-Age=0; Path=/";
    api.recordSiteConsent.mockClear();
  });

  it("offers reject, settings and accept with equal weight", () => {
    wrap();
    const bar = screen.getByTestId("site-consent-bar");
    const buttons = bar.querySelectorAll("button");
    expect([...buttons].map((button) => button.textContent)).toEqual(["Απόρριψη όλων", "Ρυθμίσεις", "Αποδοχή όλων"]);
    expect(new Set([...buttons].map((button) => button.getAttribute("style"))).size).toBe(1);
  });

  it("remembers a rejection, logs it and hides the bar", () => {
    wrap();
    fireEvent.click(screen.getByText("Απόρριψη όλων"));
    expect(screen.queryByTestId("site-consent-bar")).toBeNull();
    expect(document.cookie).toContain("palee_site_consent_kypseli=");
    expect(api.recordSiteConsent).toHaveBeenCalledWith("kypseli", expect.objectContaining({ action: "reject_all", analytics: false, marketing: false }));
  });

  it("shows no bar when the box has no tags", () => {
    wrap({ ...SITE, tracking: { ...SITE.tracking, consent_required: false } });
    expect(screen.queryByTestId("site-consent-bar")).toBeNull();
  });
});
