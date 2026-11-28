import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { PackageStartNotice, type PackageStartView } from "./PackageStartNotice";

const review: PackageStartView = {
  id: "s1",
  status: "review",
  package_name: "Unlimited",
  waiting_since: "2026-11-01",
  severity: "important",
  changes: [{ key: "price", from: 5000, to: 6000, severity: "important" }],
};

function wrap(children: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      {children}
    </NextIntlClientProvider>,
  );
}

describe("PackageStartNotice (ADR-795)", () => {
  it("a waiting package says it starts with the first session", () => {
    wrap(<PackageStartNotice start={{ ...review, status: "waiting", severity: null, changes: [] }} audience="member" />);
    expect(screen.getByText("Ξεκινά με την πρώτη σου προπόνηση")).toBeInTheDocument();
  });

  it("a price rise is important, keeps the paid price for the first period and starts with «Το κατάλαβα»", () => {
    const onAcknowledge = vi.fn();
    wrap(<PackageStartNotice start={review} audience="member" onAcknowledge={onAcknowledge} />);
    expect(screen.getByTestId("package-start-review")).toHaveAttribute("data-severity", "important");
    expect(screen.getByText("Το Unlimited κοστίζει περισσότερο τώρα")).toBeInTheDocument();
    expect(screen.getByText(/Η πρώτη περίοδος μένει στην τιμή της αγοράς/)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("package-start-acknowledge"));
    expect(onAcknowledge).toHaveBeenCalled();
  });

  it("staff see the same state without the button", () => {
    wrap(<PackageStartNotice start={{ ...review, severity: "serious" }} audience="staff" />);
    expect(screen.getByText("Το Unlimited δίνει λιγότερα τώρα")).toBeInTheDocument();
    expect(screen.queryByTestId("package-start-acknowledge")).toBeNull();
  });
});
