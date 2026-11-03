import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import type { FitnessProfile } from "@/api/training-floor";

import { FitnessProfileCard } from "./FitnessProfileCard";

const fetchFitnessProfile = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/training-floor", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/training-floor")>()),
  fetchFitnessProfile: (...args: unknown[]) => fetchFitnessProfile(...args),
}));

function profile(overrides: Partial<FitnessProfile> = {}): FitnessProfile {
  return {
    algorithm: { id: "fitness-profile", version: 1 },
    benchmarks_known: 2,
    division: null,
    neutral_standards: true,
    injury_caution: false,
    overall: { score: 61, domains_scored: 2, reason: "mean" },
    focus: [{ kind: "weakest_domain", domain: "gymnastics" }],
    domains: [
      {
        domain: "strength",
        score: 72,
        confidence: "medium",
        stale: false,
        reasons: [
          {
            benchmark: "back_squat",
            name: "Back squat",
            domain: "strength",
            value: 116.5,
            unit: "kg",
            points: 72.4,
            estimated: true,
            stale: false,
            age_days: 30,
            beaten_on: "2026-10-01",
            anchors: [],
          },
        ],
      },
      { domain: "gymnastics", score: 50, confidence: "low", stale: false, reasons: [] },
    ],
    ...overrides,
  } as FitnessProfile;
}

function renderCard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<FitnessProfileCard />, { wrapper });
}

describe("FitnessProfileCard (ADR-358, mockup d6 A)", () => {
  beforeEach(() => fetchFitnessProfile.mockReset());
  afterEach(() => window.localStorage.clear());

  it("shows five domain bars, the untested ones with how to test them", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    expect(await screen.findAllByRole("meter")).toHaveLength(5);
    expect(screen.getByRole("meter", { name: "domain_strength" })).toHaveAttribute("aria-valuenow", "72");
    expect(screen.getByText("fitnessNoTest_power")).toBeInTheDocument();
    expect(screen.getByText("fitnessOverall:61")).toBeInTheDocument();
  });

  it("«Γιατί;» lists the PRs that made the number", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    const strength = await screen.findByTestId("fitness-domain-strength");
    const why = strength.querySelector("button")!;
    expect(why).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(why);
    expect(strength).toHaveTextContent("fitnessReason:Back squat,116.5 kg,72");
    expect(strength).toHaveTextContent("fitnessEstimated");
  });

  it("then «Τι να δουλέψεις», with the injury note when there is one", async () => {
    fetchFitnessProfile.mockResolvedValue(profile({ injury_caution: true }));
    renderCard();
    const focus = await screen.findByTestId("fitness-focus");
    expect(focus).toHaveTextContent("focus_weakest_domain:domain_gymnastics");
    expect(focus).toHaveTextContent("fitnessInjury");
  });

  it("keeps the standards under «Προχωρημένα» and asks again with the one picked", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    const advanced = await screen.findByTestId("fitness-profile-advanced");
    fireEvent.click(advanced.querySelector("button")!);
    fireEvent.click(screen.getByRole("radio", { name: "division_women" }));
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenLastCalledWith("tok", "women"));
    expect(window.localStorage.getItem("palee:fitness-profile-division")).toBe("women");
  });

  it("stays out of the way when it fails", async () => {
    fetchFitnessProfile.mockRejectedValueOnce(new ApiError(500, "Server error", { code: "internal" }));
    const { container } = renderCard();
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenCalled());
    await waitFor(() => expect(container).toBeEmptyDOMElement());
  });
});
