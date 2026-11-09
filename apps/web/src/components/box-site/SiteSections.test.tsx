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

describe("SiteSections «Ωρολόγιο» (ANR 2026-11-09)", () => {
  it("shows the first day and switches days from the strip", () => {
    const section = show();
    expect(within(section).getByText("CrossFit")).toBeInTheDocument();
    expect(within(section).queryByText("Weightlifting")).not.toBeInTheDocument();

    const days = within(section).getAllByRole("tab");
    expect(days).toHaveLength(3);
    expect(days[0]).toHaveAttribute("aria-selected", "true");
    fireEvent.click(days[1]!);
    expect(days[1]).toHaveAttribute("aria-selected", "true");
    expect(within(section).getByText("Weightlifting")).toBeInTheDocument();
    expect(within(section).queryByText("CrossFit")).not.toBeInTheDocument();
  });

  it("puts classes that start together side by side in one row", () => {
    const section = show([...TIMETABLE.slice(0, 1), { ...TIMETABLE[0]!, id: "t4", name: "Open gym" }]);
    const slots = within(section).getAllByTestId("site-schedule-slot");
    expect(slots).toHaveLength(1);
    expect(within(slots[0]!).getByText("CrossFit")).toBeInTheDocument();
    expect(within(slots[0]!).getByText("Open gym")).toBeInTheDocument();
  });

  it("has no day strip when every class is on one day", () => {
    const section = show(TIMETABLE.slice(0, 1));
    expect(within(section).getByText("CrossFit")).toBeInTheDocument();
    expect(within(section).queryByRole("tab")).not.toBeInTheDocument();
  });
});
