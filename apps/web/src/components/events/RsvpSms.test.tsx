import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import type { CommunityEvent } from "@/api/events";

import { RsvpButton } from "./EventParts";

const mutate = vi.hoisted(() => vi.fn());

vi.mock("./use-events", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./use-events")>()),
  useRsvp: () => ({ mutate, isPending: false, error: null }),
}));

const inHours = (hours: number) => new Date(Date.now() + hours * 3_600_000).toISOString();

function event(overrides: Partial<CommunityEvent> = {}): CommunityEvent {
  return {
    id: "event-1",
    organization_id: "org-1",
    club_id: "club-1",
    time_zone: "Europe/Athens",
    club: { id: "club-1", name: "Box Kypseli", kind: "gym" },
    box: { name: "Box Kypseli", slug: "kypseli", logo_url: null },
    title: "Open WOD",
    starts_at: inHours(24),
    ends_at: inHours(25),
    place: { name: "Box Kypseli", address: "Fokionos 1", latitude: null, longitude: null, location_id: "loc-1" },
    capacity: 10,
    spots_left: 3,
    going_count: 7,
    waitlist_count: 0,
    price_cents: 0,
    currency: "EUR",
    open_to_non_members: false,
    guest_pass_allowed: false,
    guests_per_member: 0,
    good_for_friends: false,
    cancelled: false,
    can_rsvp: true,
    can_manage: false,
    sms_enabled: true,
    sms_offered: true,
    my: null,
    audience: "club",
    host: { kind: "business", organization_id: "org-1", name: "Box Kypseli", slug: "kypseli", logo_url: null, person: null },
    cohosts: [],
    ...overrides,
  };
}

function renderButton(value: CommunityEvent, compact = false) {
  return render(
    <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
      <RsvpButton event={value} compact={compact} />
    </NextIntlClientProvider>,
  );
}

beforeEach(() => mutate.mockReset());

describe("SMS on «I'm going» (W3 screen 5 A)", () => {
  it("is never ticked by itself and shows the mobile only once ticked", () => {
    renderButton(event());
    const box = screen.getByRole("checkbox", { name: new RegExp(en.Events.smsAsk) });
    expect(box).not.toBeChecked();
    expect(screen.queryByLabelText(en.Events.smsPhone)).toBeNull();

    fireEvent.click(box);
    const phone = screen.getByLabelText(en.Events.smsPhone);
    const going = screen.getByRole("button", { name: en.Events.going });
    expect(going).toBeDisabled();

    fireEvent.change(phone, { target: { value: "6912345678" } });
    fireEvent.click(going);
    expect(mutate).toHaveBeenCalledWith({ going: true, sms: { phone: "6912345678", locale: "en" } });
  });

  it("joins without SMS when the box is left unticked", () => {
    renderButton(event());
    fireEvent.click(screen.getByRole("button", { name: en.Events.going }));
    expect(mutate).toHaveBeenCalledWith(true);
  });

  it("does not offer SMS where the organiser sends none", () => {
    renderButton(event({ sms_offered: false }));
    expect(screen.queryByRole("checkbox")).toBeNull();
  });

  it("does not offer SMS on the compact card", () => {
    renderButton(event(), true);
    expect(screen.queryByRole("checkbox")).toBeNull();
  });
});
