import { act, fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { GuestLanding } from "@/components/landing/GuestLanding";
import { PALEE_TAGLINE } from "@/components/branding/PaleeTagline";

vi.mock("next-intl", () => {
  const translate = (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key;
  translate.rich = (key: string) => key;
  return { useLocale: () => "en", useTranslations: () => translate };
});

vi.mock("@/components/auth-console", () => ({
  AuthPanel: ({ initialMode }: { initialMode: string }) => <p>auth-panel:{initialMode}</p>,
}));

describe("GuestLanding (ADR-555)", () => {
  beforeEach(() => vi.useRealTimers());

  it("shows the tagline in its own words and no form until asked", () => {
    render(<GuestLanding />);
    const taglines = screen.getAllByTestId("palee-tagline");
    expect(taglines.length).toBeGreaterThan(0);
    for (const tagline of taglines) expect(tagline.textContent?.replace(/\s+/g, " ")).toBe(PALEE_TAGLINE);
    expect(screen.queryByText(/auth-panel/)).toBeNull();
  });

  it("opens the form over an inert page, and closes it again", () => {
    const onAuthOpen = vi.fn();
    render(<GuestLanding onAuthOpen={onAuthOpen} />);
    fireEvent.click(screen.getAllByRole("button", { name: "getStarted" })[0]);

    const drawer = screen.getByTestId("landing-auth-drawer");
    expect(within(drawer).getByText("auth-panel:register")).toBeTruthy();
    expect(screen.getByTestId("guest-landing").hasAttribute("inert")).toBe(true);
    expect(onAuthOpen).toHaveBeenCalled();

    fireEvent.click(within(drawer).getByRole("button", { name: "close" }));
    expect(screen.queryByTestId("landing-auth-drawer")).toBeNull();
    expect(screen.getByTestId("guest-landing").hasAttribute("inert")).toBe(false);
  });

  it("opens straight on the form for /login", () => {
    render(<GuestLanding initialMode="login" />);
    expect(screen.getByText("auth-panel:login")).toBeTruthy();
  });

  it("turns the story when its bar runs out, and a hold pauses without turning", () => {
    vi.useFakeTimers();
    render(<GuestLanding />);
    const position = () => screen.getByText(/stories\.position/).textContent;
    expect(position()).toContain('"current":1');

    // jsdom has no AnimationEvent, so React listens for the prefixed name.
    const bar = screen.getByTestId("landing-story-bar");
    act(() => {
      bar.dispatchEvent(new Event("webkitAnimationEnd", { bubbles: true }));
    });
    expect(position()).toContain('"current":2');

    const stage = screen.getByTestId("landing-story-stage");
    fireEvent.pointerDown(stage, { button: 0, clientX: 300 });
    act(() => vi.advanceTimersByTime(300));
    expect(screen.getByTestId("landing-story-bar").getAttribute("data-paused")).toBe("true");
    expect(screen.getByText("stories.paused")).toBeTruthy();
    fireEvent.pointerUp(stage, { button: 0, clientX: 300 });
    expect(position()).toContain('"current":2');
    expect(screen.getByTestId("landing-story-bar").getAttribute("data-paused")).toBe("false");
  });

  it("pauses for good with the pause button", () => {
    render(<GuestLanding />);
    fireEvent.click(screen.getByRole("button", { name: "stories.pause" }));
    expect(screen.getByTestId("landing-story-bar").getAttribute("data-paused")).toBe("true");
    expect(screen.getByRole("button", { name: "stories.play" })).toBeTruthy();
  });
});
