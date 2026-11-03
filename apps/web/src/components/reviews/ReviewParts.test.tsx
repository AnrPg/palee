import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../messages/el.json";

import type { GoogleListing } from "@/api/box-site";

import { GoogleReviews } from "./ReviewParts";

describe("GoogleReviews (ADR-387 amendment)", () => {
  it("shows only the Google rating and the number of reviews, «Από το Google», no review texts", () => {
    const google = {
      name: "Box Κυψέλη",
      rating: 4.8,
      count: 126,
      maps_uri: "https://maps.google.com/?cid=1",
      write_review_url: "https://search.google.com/local/writereview?placeid=x",
      fetched_at: "2026-11-03T08:00:00Z",
      // An older answer may still carry texts: they are never shown.
      reviews: [{ author_name: "Μαρία Π.", text: "Υπέροχοι coaches.", rating: 5 }],
    } as unknown as GoogleListing;

    render(
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <GoogleReviews google={google} />
      </NextIntlClientProvider>,
    );

    const section = screen.getByTestId("google-reviews");
    expect(section.textContent).toContain("Από το Google");
    expect(section.textContent).toContain("4,8");
    expect(section.textContent).toContain("126 κριτικές Google");
    expect(section.textContent).not.toContain("Υπέροχοι coaches.");
    expect(section.textContent).not.toContain("Μαρία Π.");
    expect(section.querySelectorAll("li")).toHaveLength(0);
    expect(screen.getByRole("link").getAttribute("href")).toBe("https://maps.google.com/?cid=1");
  });
});
