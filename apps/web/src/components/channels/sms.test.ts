import { afterEach, describe, expect, it } from "vitest";

import type { ChannelContact, MyChannels } from "@/api/channels";

import {
  bookingAskDeclined,
  budgetChoices,
  budgetState,
  consentAnswered,
  consentGranted,
  deliveryCounts,
  formatCents,
  monthOf,
  providerFor,
  recentMonths,
  rememberBookingAskDeclined,
  senderError,
  shouldAskAfterBooking,
  smsErrorCode,
  spendParts,
  suggestSender,
} from "./sms";

const contact = (overrides: Partial<ChannelContact> = {}): ChannelContact => ({
  id: "c1",
  phone: "+306912345678",
  locale: "el",
  consents: [],
  ...overrides,
});

describe("sms rules", () => {
  afterEach(() => window.localStorage.clear());

  it("formats cents in the reader's language", () => {
    expect(formatCents(364, "EUR", "el")).toMatch(/3,64/);
    expect(formatCents(364, "EUR", "en")).toMatch(/3\.64/);
  });

  it("keeps the saved budget among the choices", () => {
    expect(budgetChoices(2000)).toEqual([5, 10, 20, 30, 50, 100, 200]);
    expect(budgetChoices(1500)).toContain(15);
  });

  it("checks the sender name as the API does", () => {
    expect(senderError("BoxKypseli")).toBeNull();
    expect(senderError("")).toBeNull();
    expect(senderError("BoxKypseli12")).toBe("tooLong");
    expect(senderError("Κυψέλη")).toBe("latinOnly");
    expect(senderError("12345")).toBe("needsLetter");
    expect(senderError("+306912345678")).toBeNull();
    expect(senderError("+12")).toBe("latinOnly");
  });

  it("suggests a Latin sender from the box name", () => {
    expect(suggestSender("CrossFit Kypseli Athens")).toBe("CrossFitKyp");
    expect(suggestSender("Box Κυψέλη")).toBe("Box");
  });

  it("picks Brevo for Palee's account, else what the box has", () => {
    const providers = [
      { provider: "sandbox", account_modes: ["palee", "own"] },
      { provider: "brevo", account_modes: ["palee", "own"] },
    ];
    expect(providerFor(null, providers)).toBe("brevo");
    expect(providerFor(null, [providers[0]])).toBe("sandbox");
    expect(providerFor({ provider: "sandbox" } as never, providers)).toBe("sandbox");
  });

  it("names months on the box's clock", () => {
    const lateUtc = new Date("2026-10-31T23:30:00Z");
    expect(monthOf(lateUtc, "Europe/Athens")).toBe("2026-11");
    expect(monthOf(lateUtc, "UTC")).toBe("2026-10");
    expect(recentMonths(lateUtc, "Europe/Athens", 3)).toEqual(["2026-11", "2026-10", "2026-09"]);
    expect(recentMonths(new Date("2026-01-10T12:00:00Z"), "UTC", 2)).toEqual(["2026-01", "2025-12"]);
  });

  it("splits the month bar by source against the cap", () => {
    const parts = spendParts({
      cap_cents: 2000,
      spent_cents: 364,
      by_source: { automation: { cents: 240, count: 20 }, staff: { cents: 124, count: 18 } },
    });
    expect(parts).toEqual([
      { source: "automation", cents: 240, count: 20, percent: 12 },
      { source: "staff", cents: 124, count: 18, percent: 6.2 },
    ]);
    const over = spendParts({ cap_cents: 100, spent_cents: 300, by_source: { staff: { cents: 300, count: 3 } } });
    expect(over[0].percent).toBe(100);
  });

  it("counts arrived, failed and waiting", () => {
    expect(deliveryCounts({ delivered: 30, sent: 5, failed: 2, queued: 1 })).toEqual({ delivered: 35, failed: 2, waiting: 1 });
    expect(deliveryCounts(undefined)).toEqual({ delivered: 0, failed: 0, waiting: 0 });
  });

  it("says when the month nears or reaches the cap", () => {
    expect(budgetState(364, 2000)).toBe("ok");
    expect(budgetState(1600, 2000)).toBe("near");
    expect(budgetState(2000, 2000)).toBe("full");
    expect(budgetState(1, 0)).toBe("full");
  });

  it("reads consents; STOP ends them all", () => {
    const yes = contact({ consents: [{ channel: "sms", purpose: "service", granted: true }] });
    expect(consentGranted(yes, "service")).toBe(true);
    expect(consentGranted(yes, "marketing")).toBe(false);
    expect(consentGranted({ ...yes, opted_out_at: "2026-11-12T10:00:00Z" }, "service")).toBe(false);
    expect(consentAnswered(contact({ consents: [{ channel: "sms", purpose: "service", granted: false }] }), "service")).toBe(true);
    expect(consentAnswered(null, "service")).toBe(false);
  });

  it("asks after a booking once, only where the box sends SMS", () => {
    const fresh: MyChannels = { channels: ["sms"], contact: null };
    expect(shouldAskAfterBooking(fresh, false)).toBe(true);
    expect(shouldAskAfterBooking(fresh, true)).toBe(false);
    expect(shouldAskAfterBooking({ channels: [], contact: null }, false)).toBe(false);
    expect(
      shouldAskAfterBooking({ channels: ["sms"], contact: contact({ consents: [{ channel: "sms", purpose: "service", granted: false }] }) }, false),
    ).toBe(false);
  });

  it("remembers «Όχι τώρα» per box and person", () => {
    expect(bookingAskDeclined("kypseli", "u1")).toBe(false);
    rememberBookingAskDeclined("kypseli", "u1");
    expect(bookingAskDeclined("kypseli", "u1")).toBe(true);
    expect(bookingAskDeclined("other", "u1")).toBe(false);
  });

  it("knows the error codes it explains", () => {
    expect(smsErrorCode("channels_demo_mode")).toBe("channels_demo_mode");
    expect(smsErrorCode("nope")).toBeNull();
  });
});
