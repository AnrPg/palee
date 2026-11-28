import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import en from "../../messages/en.json";

const refreshSession = vi.fn();

vi.mock("@/api/auth", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/auth")>()),
  refreshSession: (signal?: AbortSignal) => refreshSession(signal),
}));
vi.mock("@/api/profile", () => ({ reportMyTimeZone: vi.fn(() => Promise.resolve()) }));
vi.mock("@/lib/push-subscription", () => ({
  clearWorkoutCache: vi.fn(() => Promise.resolve()),
  clearBrowserPushSubscription: vi.fn(() => Promise.resolve()),
  setWorkoutCacheUser: vi.fn(() => Promise.resolve()),
}));
vi.mock("@/lib/realtime", () => ({ resetRealtimeSocket: vi.fn() }));

import { SESSION_RESTORE_TIMEOUT_MS, SessionProvider, useSession } from "./session-provider";

function Probe() {
  const { status, restoreFailed } = useSession();
  return <p data-testid="probe">{`${status}:${restoreFailed}`}</p>;
}

function renderProvider(locale = "en") {
  return render(
    <NextIntlClientProvider locale={locale} messages={en}>
      <QueryClientProvider client={new QueryClient()}>
        <SessionProvider>
          <Probe />
        </SessionProvider>
      </QueryClientProvider>
    </NextIntlClientProvider>,
  );
}

const user = { id: "user-1", role: "member", preferred_locale: "el" };
const reload = vi.fn();

beforeEach(() => {
  refreshSession.mockReset();
  reload.mockReset();
  window.sessionStorage.clear();
  vi.spyOn(window, "location", "get").mockReturnValue({ ...window.location, reload } as Location);
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("SessionProvider restore", () => {
  it("never stays on the splash: a hung restore ends as a failed restore", async () => {
    vi.useFakeTimers();
    let aborted = false;
    refreshSession.mockImplementation((signal: AbortSignal) => {
      signal.addEventListener("abort", () => (aborted = true));
      return new Promise(() => undefined);
    });

    renderProvider();
    expect(screen.getByTestId("probe").textContent).toBe("loading:false");

    await act(async () => {
      await vi.advanceTimersByTimeAsync(SESSION_RESTORE_TIMEOUT_MS);
    });

    expect(screen.getByTestId("probe").textContent).toBe("guest:true");
    expect(aborted).toBe(true);
  });

  it("a failing restore is reported as failed, no saved sign-in is just a guest", async () => {
    refreshSession.mockRejectedValueOnce(new Error("network"));
    const { unmount } = renderProvider();
    await screen.findByText("guest:true");
    unmount();

    refreshSession.mockResolvedValueOnce({});
    const second = renderProvider();
    await screen.findByText("guest:false");
    second.unmount();

    // A refused refresh (no or expired sign-in cookie) is a plain guest too.
    refreshSession.mockRejectedValueOnce(new ApiError(401, "unauthorized", { error: "unauthorized" }));
    renderProvider();
    await screen.findByText("guest:false");
  });

  it("compares the person's language with the rendered locale, not a translated <html lang>", async () => {
    // Chrome's translator rewrote <html lang> to English on a Greek page.
    document.documentElement.lang = "en";
    refreshSession.mockResolvedValue({ access_token: "token", user });

    renderProvider("el");
    await screen.findByText("authenticated:false");

    expect(reload).not.toHaveBeenCalled();
  });

  it("reloads into the person's language at most once per tab", async () => {
    refreshSession.mockResolvedValue({ access_token: "token", user });

    const first = renderProvider("en");
    await screen.findByText("authenticated:false");
    expect(reload).toHaveBeenCalledTimes(1);
    first.unmount();

    // The reloaded page is still English (the cookie did not stick): no loop.
    renderProvider("en");
    await screen.findByText("authenticated:false");
    expect(reload).toHaveBeenCalledTimes(1);
  });
});
