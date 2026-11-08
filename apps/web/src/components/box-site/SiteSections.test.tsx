import { fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import { publicPackagesKey } from "@/api/my-payments";

import el from "../../../messages/el.json";

import { SiteSections } from "./SiteSections";
import { boxPage, boxSite, PACKAGES } from "./templates/site.test-fixtures";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }), usePathname: () => "/b/box-kypseli", useSearchParams: () => new URLSearchParams() }));

const TIMETABLE = [
  { id: "t1", name: "CrossFit", scheduled_at: "2026-11-04T15:00:00Z", duration_minutes: 60, class_type_id: null, location_id: null },
  { id: "t2", name: "Weightlifting", scheduled_at: "2026-11-05T05:00:00Z", duration_minutes: 60, class_type_id: null, location_id: null },
  { id: "t3", name: "Gymnastics", scheduled_at: "2026-11-06T16:00:00Z", duration_minutes: 45, class_type_id: null, location_id: null },
];

function show(timetable = TIMETABLE) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: Infinity } } });
  queries.setQueryData(publicPackagesKey("box-kypseli"), { packages: PACKAGES, online_payments: false });
  render(
    <QueryClientProvider client={queries}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <SiteSections
          page={boxPage()}
          site={boxSite({ sections: ["schedule"], timetable })}
          language="box"
          basePath="/b/box-kypseli"
          onOpenPhoto={() => undefined}
          onRequest={() => undefined}
        />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return screen.getByTestId("site-schedule");
}

describe("SiteSections «Πρόγραμμα»", () => {
  it("shows the first day and opens the rest of the week on request", () => {
    const section = show();
    expect(within(section).getByText("CrossFit")).toBeInTheDocument();
    expect(within(section).queryByText("Weightlifting")).not.toBeInTheDocument();

    const more = within(section).getByRole("button", { name: "Όλη η εβδομάδα · 2 ακόμα μέρες" });
    expect(more).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(more);
    expect(within(section).getByText("Weightlifting")).toBeInTheDocument();
    expect(within(section).getByText("Gymnastics")).toBeInTheDocument();

    const less = within(section).getByRole("button", { name: "Λιγότερα" });
    expect(less).toHaveAttribute("aria-expanded", "true");
    fireEvent.click(less);
    expect(within(section).queryByText("Gymnastics")).not.toBeInTheDocument();
  });

  it("has no expander when every class is on one day", () => {
    const section = show(TIMETABLE.slice(0, 1));
    expect(within(section).getByText("CrossFit")).toBeInTheDocument();
    expect(within(section).queryByRole("button")).not.toBeInTheDocument();
  });

  it("counts a single remaining day in the singular", () => {
    const section = show(TIMETABLE.slice(0, 2));
    expect(within(section).getByRole("button", { name: "Όλη η εβδομάδα · 1 ακόμα μέρα" })).toBeInTheDocument();
  });
});
