import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import type { ScanRequest } from "@/api/check-in";
import { ApiError } from "@/api/client";
import { openDoor } from "@/api/doors";
import { fetchMarketingConsent, saveEmailList, saveMarketingConsent } from "@/api/integrations";
import { BoxEmailListCard } from "@/components/integrations/BoxEmailListCard";
import { EmailListSettings } from "@/components/integrations/EmailListSettings";
import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";

import { DoorAnswerCard, opensDoor } from "./DoorAnswerCard";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/api/doors", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/doors")>()),
  openDoor: vi.fn(),
}));
vi.mock("@/api/integrations", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/integrations")>()),
  fetchMarketingConsent: vi.fn(),
  saveMarketingConsent: vi.fn(),
  fetchEmailList: vi.fn(async () => null),
  saveEmailList: vi.fn(),
}));

function wrap(children: ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const body = { code: "door-qr" } as unknown as ScanRequest;
const membership = { organization: { slug: "box", name: "Box Kypseli" }, settings: null } as unknown as BoxExtensionProps["membership"];

beforeEach(() => vi.clearAllMocks());

describe("door answer after a scan (W10 screen 5 A)", () => {
  it("opens only from the door QR or NFC, never for a visitor", () => {
    expect(opensDoor("door", { outcome: "checked_in" } as never)).toBe(true);
    expect(opensDoor("nfc", { outcome: "checked_in" } as never)).toBe(true);
    expect(opensDoor("door", { outcome: "visitor" } as never)).toBe(false);
    expect(opensDoor("poster", { outcome: "checked_in" } as never)).toBe(false);
  });

  it("says the door opened, for how long", () => {
    wrap(<DoorAnswerCard token="access" body={body} error={null} result={{ opened: true, reason: "booked_class", seconds: 5, door: { id: "d1", name: "Main door" } } as never} />);
    expect(screen.getByText("The door opened")).toBeTruthy();
    expect(screen.getByText(/Main door/)).toBeTruthy();
  });

  it("asks which door and opens the chosen one with the same scan", async () => {
    vi.mocked(openDoor).mockResolvedValue({ opened: true, reason: "booked_class", seconds: 5, door: { id: "b", name: "Back door" } } as never);
    const error = new ApiError(409, "choose", { code: "choose_door", params: { doors: [{ id: "a", name: "Front door" }, { id: "b", name: "Back door" }] } });
    wrap(<DoorAnswerCard token="access" body={body} error={error} result={null} />);
    fireEvent.click(screen.getByRole("button", { name: /Back door/ }));
    await waitFor(() => expect(screen.getByText("The door opened")).toBeTruthy());
    expect(openDoor).toHaveBeenCalledWith("access", { code: "door-qr", door_id: "b" });
  });

  it("says nothing where the branch has no door", () => {
    const { container } = wrap(<DoorAnswerCard token="access" body={body} error={new ApiError(404, "none", { code: "no_door_here" })} result={null} />);
    expect(container.textContent).toBe("");
  });
});

describe("member email consent (W10 screen 3 A)", () => {
  it("stays hidden while the box has no email list", async () => {
    vi.mocked(fetchMarketingConsent).mockResolvedValue({ list_connected: false, granted: false, granted_at: null } as never);
    const { container } = wrap(<BoxEmailListCard membership={membership} providerKind="gym" />);
    await waitFor(() => expect(fetchMarketingConsent).toHaveBeenCalled());
    expect(container.querySelector("[data-testid='box-email-consent']")).toBeNull();
  });

  it("saves the member's own yes", async () => {
    vi.mocked(fetchMarketingConsent).mockResolvedValue({ list_connected: true, granted: false, granted_at: null } as never);
    vi.mocked(saveMarketingConsent).mockResolvedValue({ list_connected: true, granted: true, granted_at: "2026-11-03T10:00:00Z" } as never);
    wrap(<BoxEmailListCard membership={membership} providerKind="gym" />);
    const toggle = await screen.findByRole("switch", { name: "Email updates from Box Kypseli" });
    fireEvent.click(toggle);
    await waitFor(() => expect(saveMarketingConsent).toHaveBeenCalledWith("access", "box", true));
  });
});

describe("email list connection (W10 screen 3 A)", () => {
  it("keeps missing fields inside the form and does not send", async () => {
    wrap(<EmailListSettings token="access" />);
    fireEvent.click(await screen.findByRole("button", { name: "Check and connect" }));
    expect(screen.getByText("Enter the service's API key.")).toBeTruthy();
    expect(screen.getByText("Enter the list's id.")).toBeTruthy();
    expect(saveEmailList).not.toHaveBeenCalled();
  });
});
