import { QueryClient } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchGuideProgress } from "@/api/guides";

import { shouldOfferCalendar } from "./once-asked";
import { rememberCalendarOffer } from "./training-floor";

vi.mock("@/api/guides", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/guides")>()),
  fetchGuideProgress: vi.fn(),
}));

const row = (guide_id: string) => ({ guide_id, status: "dismissed" }) as never;

describe("calendar offer asked once on every device (CP-E4)", () => {
  afterEach(() => window.localStorage.clear());

  it("is offered when neither this device nor the server has an answer", async () => {
    vi.mocked(fetchGuideProgress).mockResolvedValue({ guides: [row("shop")] } as never);
    expect(await shouldOfferCalendar(new QueryClient(), "tok", "u1")).toBe(true);
  });

  it("is not offered when another device already answered", async () => {
    vi.mocked(fetchGuideProgress).mockResolvedValue({ guides: [row("calendar_offer")] } as never);
    expect(await shouldOfferCalendar(new QueryClient(), "tok", "u1")).toBe(false);
  });

  it("is not offered when this device answered, without asking the server", async () => {
    vi.mocked(fetchGuideProgress).mockClear();
    rememberCalendarOffer("u1", "no");
    expect(await shouldOfferCalendar(new QueryClient(), "tok", "u1")).toBe(false);
    expect(fetchGuideProgress).not.toHaveBeenCalled();
  });

  it("is not offered when signed out", async () => {
    expect(await shouldOfferCalendar(new QueryClient(), null, "u1")).toBe(false);
  });
});

describe("SMS question ids (W3 screen 2 B)", () => {
  it("keeps one id per box in the progress ids' alphabet", async () => {
    const { smsAskGuideId } = await import("./once-asked");
    expect(smsAskGuideId("crossfit-kypseli")).toBe("sms_ask_crossfit_kypseli");
    expect(smsAskGuideId("x".repeat(80))).toHaveLength(48);
  });
});
