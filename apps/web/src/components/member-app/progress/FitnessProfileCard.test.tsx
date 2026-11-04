import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { ProgressRange } from "@/api/account-training";
import { ApiError } from "@/api/client";
import type { FitnessProfile } from "@/api/training-floor";

import { FitnessProfileCard } from "./FitnessProfileCard";

const fetchFitnessProfile = vi.fn();
const putFitnessSettings = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/training-floor", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/training-floor")>()),
  fetchFitnessProfile: (...args: unknown[]) => fetchFitnessProfile(...args),
  putFitnessSettings: (...args: unknown[]) => putFitnessSettings(...args),
}));

function profile(overrides: Partial<FitnessProfile> = {}): FitnessProfile {
  return {
    algorithm: { id: "fitness-profile", version: 2 },
    display: { mode: "all", set_by: "self" },
    settings: { body_weight_kg: null, birth_year: null, display: "all" },
    inputs: { body_weight_kg: null, age_band: null, age_percent: null, age_ready: false },
    period_from: null,
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
            basis: "absolute",
          },
        ],
      },
      { domain: "gymnastics", score: 50, confidence: "low", stale: false, reasons: [] },
    ],
    ...overrides,
  } as FitnessProfile;
}

function renderCard(range?: ProgressRange) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<FitnessProfileCard range={range} />, { wrapper });
}

describe("FitnessProfileCard (ADR-358, mockup d6 A)", () => {
  beforeEach(() => {
    fetchFitnessProfile.mockReset();
    putFitnessSettings.mockReset();
  });
  afterEach(() => window.localStorage.clear());

  it("shows five domain bars, the untested ones with how to test them", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    expect(await screen.findAllByRole("meter")).toHaveLength(5);
    expect(screen.getByRole("meter", { name: "domain_strength" })).toHaveAttribute("aria-valuenow", "72");
    expect(screen.getByText("fitnessNoTest_power")).toBeInTheDocument();
    expect(screen.getByText("fitnessOverall:61")).toBeInTheDocument();
  });

  it("stays out of the way, without breaking Progress, when the answer is malformed", async () => {
    fetchFitnessProfile.mockResolvedValue({} as FitnessProfile);
    const { container } = renderCard();
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenCalled());
    await waitFor(() => expect(container.querySelector("[data-testid=fitness-profile]")).toBeNull());
    expect(screen.queryByRole("meter")).toBeNull();
  });

  it("«Γιατί;» lists the PRs that made the number", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    const strength = await screen.findByTestId("fitness-domain-strength");
    const why = strength.querySelector("button")!;
    expect(why).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(why);
    expect(strength).toHaveTextContent("fitnessReason:Back squat,116.5 kg,72");
    expect(strength).toHaveTextContent("fitnessStepPr");
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
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenLastCalledWith("tok", "women", "all"));
    expect(window.localStorage.getItem("palee:fitness-profile-division")).toBe("women");
  });

  it("stays out of the way when it fails", async () => {
    fetchFitnessProfile.mockRejectedValueOnce(new ApiError(500, "Server error", { code: "internal" }));
    const { container } = renderCard();
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenCalled());
    await waitFor(() => expect(container).toBeEmptyDOMElement());
  });

  it("asks for the change over Πρόοδος's period and shows it next to the domain, with a grey tick (ADR-395 §3 A)", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        period_from: "2026-08-05",
        overall: { score: 61, domains_scored: 2, reason: "mean", change: 5 },
        domains: [
          { domain: "strength", score: 60, previous_score: 54, change: 6, confidence: "low", stale: false, reasons: [] },
          { domain: "metcon", score: 63, previous_score: 66, change: -3, confidence: "low", stale: false, reasons: [] },
          { domain: "gymnastics", score: 40, previous_score: 40, change: 0, confidence: "low", stale: false, reasons: [] },
        ],
      }),
    );
    renderCard("12w");
    const strength = await screen.findByTestId("fitness-domain-strength");
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenLastCalledWith("tok", null, "12w"));
    const chip = within(strength).getByTestId("fitness-change");
    expect(chip).toHaveAttribute("data-direction", "up");
    expect(chip).toHaveTextContent("▲ +6");
    expect(chip).toHaveTextContent("fitnessChangeUp:6");
    // The chip sits with the label; the score stands alone on the right.
    expect(chip.parentElement).toHaveTextContent("domain_strength");
    expect(chip.parentElement).not.toHaveTextContent("60");
    expect(within(strength).getByTestId("fitness-previous-tick")).toHaveStyle({ left: "54%" });
    expect(within(screen.getByTestId("fitness-domain-metcon")).getByTestId("fitness-change")).toHaveTextContent("▼ −3");
    expect(within(screen.getByTestId("fitness-domain-gymnastics")).getByTestId("fitness-change")).toHaveAttribute("data-direction", "same");
    expect(screen.queryByTestId("fitness-domain-power")!.querySelector("[data-testid=fitness-change]")).toBeNull();
    expect(screen.getByText(/fitnessPreviousTick/)).toBeInTheDocument();
  });

  it("«Γιατί;» goes step by step: PR, 1RM, ÷ body weight, scale, what the next level takes (ADR-395 §1 A)", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        inputs: { body_weight_kg: 60, age_band: null, age_percent: null, age_ready: false },
        domains: [
          {
            domain: "strength",
            score: 68,
            confidence: "low",
            stale: false,
            reasons: [
              {
                benchmark: "back_squat",
                name: "Back squat",
                domain: "strength",
                value: 77,
                unit: "kg",
                points: 68,
                estimated: true,
                stale: false,
                age_days: 30,
                beaten_on: "2026-09-12",
                load: 70,
                reps: 3,
                basis: "body_weight",
                ratio: 1.28,
                body_weight_kg: 60,
                age_band: null,
                age_percent: null,
                anchors: [
                  { value: 0.7, points: 20 },
                  { value: 1.1, points: 50 },
                  { value: 1.35, points: 75 },
                  { value: 1.7, points: 95 },
                ],
                next: { points: 75, value: 81 },
              },
            ],
          },
        ],
      }),
    );
    renderCard();
    const strength = await screen.findByTestId("fitness-domain-strength");
    fireEvent.click(within(strength).getByRole("button", { name: /fitnessWhy/ }));
    const steps = within(strength).getByTestId("fitness-why-back_squat");
    expect(steps).toHaveTextContent("fitnessStepPrLift:Back squat,70,3");
    expect(within(steps).getByTestId("fitness-step-one-rm")).toHaveTextContent("70 fitnessKg × (1 + 3 ÷ 30) ≈ 77 fitnessKg");
    expect(within(steps).getByTestId("fitness-step-ratio")).toHaveTextContent("77 fitnessKg ÷ 60 fitnessKg = 1.28 ×");
    expect(within(steps).getByTestId("fitness-scale")).toHaveTextContent("1.35 ×");
    expect(within(steps).getByTestId("fitness-scale-marker")).toHaveStyle({ left: "68%" });
    // The drawn scale is aria-hidden; its anchors are read out as a list.
    expect(within(steps).getByTestId("fitness-scale")).toHaveAttribute("aria-hidden", "true");
    const anchors = within(within(steps).getByTestId("fitness-scale-anchors")).getAllByRole("listitem");
    expect(anchors.map((item) => item.textContent)).toEqual([
      "0.70 ×: fitnessStepPoints:20",
      "1.10 ×: fitnessStepPoints:50",
      "1.35 ×: fitnessStepPoints:75",
      "1.70 ×: fitnessStepPoints:95",
    ]);
    expect(within(steps).getByTestId("fitness-step-next")).toHaveTextContent("fitnessStepNextKg:75,81,4");
    expect(within(steps).queryByTestId("fitness-step-age")).toBeNull();
  });

  it("skips the ratio step on an absolute reading and says when the age band eased the standards", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        domains: [
          {
            domain: "metcon",
            score: 68,
            confidence: "low",
            stale: false,
            reasons: [
              {
                benchmark: "fran",
                name: "Fran",
                domain: "metcon",
                value: 360,
                unit: "mins_secs",
                points: 68,
                estimated: false,
                stale: false,
                age_days: 30,
                beaten_on: "2026-09-12",
                load: null,
                reps: null,
                basis: "absolute",
                ratio: null,
                body_weight_kg: null,
                age_band: "40_44",
                age_percent: 5,
                anchors: [{ value: 300, points: 75 }],
                next: { points: 75, value: 315 },
              },
            ],
          },
        ],
      }),
    );
    renderCard();
    const metcon = await screen.findByTestId("fitness-domain-metcon");
    fireEvent.click(within(metcon).getByRole("button", { name: /fitnessWhy/ }));
    expect(within(metcon).queryByTestId("fitness-step-ratio")).toBeNull();
    expect(within(metcon).queryByTestId("fitness-step-one-rm")).toBeNull();
    expect(within(metcon).getByTestId("fitness-step-age")).toHaveTextContent("fitnessStepAge:40–44");
    expect(within(metcon).getByTestId("fitness-step-next")).toHaveTextContent("fitnessStepNextTime:75,5:15,0:45");
  });

  it("«Μόνο πρόοδος» shows only the direction per domain, no scores or bars (ADR-395 §4 A)", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        display: { mode: "progress_only", set_by: "self" },
        settings: { body_weight_kg: null, birth_year: null, display: "progress_only" },
        overall: null,
        domains: [
          { domain: "strength", tested: true, direction: "up" },
          { domain: "metcon", tested: true, direction: null },
          { domain: "power", tested: false, direction: null },
        ],
      } as Partial<FitnessProfile>),
    );
    renderCard("12w");
    const strength = await screen.findByTestId("fitness-domain-strength");
    expect(within(strength).getByTestId("fitness-direction")).toHaveTextContent("fitnessDirection_up");
    expect(screen.getByTestId("fitness-domain-metcon")).toHaveTextContent("fitnessDirectionNone");
    expect(screen.getByTestId("fitness-domain-power")).toHaveTextContent("fitnessNotTested");
    expect(screen.queryByRole("meter")).toBeNull();
    expect(screen.queryByText(/fitnessOverall/)).toBeNull();
    expect(screen.queryByRole("button", { name: /fitnessWhy/ })).toBeNull();
    expect(screen.getByTestId("fitness-focus")).toBeInTheDocument();
  });

  it("«Τίποτα» is one calm line with a way back to the settings", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        display: { mode: "none", set_by: "self" },
        settings: { body_weight_kg: null, birth_year: null, display: "none" },
        overall: null,
        domains: [],
        focus: [],
      }),
    );
    renderCard();
    const hidden = await screen.findByTestId("fitness-hidden");
    expect(hidden).toHaveTextContent("fitnessHidden");
    expect(screen.queryByRole("meter")).toBeNull();
    expect(screen.queryByTestId("fitness-focus")).toBeNull();
    expect(screen.queryByTestId("fitness-settings")).toBeNull();
    fireEvent.click(within(hidden).getByRole("button", { name: "fitnessHiddenChange" }));
    expect(await screen.findByTestId("fitness-settings")).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: "fitnessDisplay_none" })).toHaveAttribute("aria-checked", "true");
  });

  it("says when the coach set it, and explains that a looser own choice does not loosen it", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({
        display: { mode: "progress_only", set_by: "coach" },
        settings: { body_weight_kg: null, birth_year: null, display: "all" },
        overall: null,
        domains: [{ domain: "strength", tested: true, direction: "same" }],
      } as Partial<FitnessProfile>),
    );
    renderCard();
    expect(await screen.findByTestId("fitness-set-by-coach")).toHaveTextContent("fitnessSetByCoach");
    fireEvent.click(screen.getByTestId("fitness-profile-advanced").querySelector("button")!);
    const limit = screen.getByTestId("fitness-coach-limit");
    expect(limit).toHaveTextContent("fitnessCoachLimit:fitnessDisplay_progress_only");
    expect(limit).toHaveTextContent("fitnessCoachLimitLooser");
    fireEvent.click(screen.getByRole("radio", { name: "fitnessDisplay_none" }));
    expect(screen.getByTestId("fitness-coach-limit")).not.toHaveTextContent("fitnessCoachLimitLooser");
  });

  it("saves body weight and what to show from «Προχωρημένα», asks for no birth year until the age bands count", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    putFitnessSettings.mockResolvedValue({ body_weight_kg: 60.5, birth_year: null, display: "progress_only" });
    renderCard();
    fireEvent.click((await screen.findByTestId("fitness-profile-advanced")).querySelector("button")!);
    expect(screen.queryByLabelText("fitnessBirthYear")).toBeNull();
    const save = screen.getByRole("button", { name: "fitnessSave" });
    expect(save).toBeDisabled();
    fireEvent.change(screen.getByLabelText("fitnessBodyWeight"), { target: { value: "60,5" } });
    fireEvent.click(screen.getByRole("radio", { name: "fitnessDisplay_progress_only" }));
    fireEvent.click(save);
    await waitFor(() =>
      expect(putFitnessSettings).toHaveBeenCalledWith("tok", { body_weight_kg: 60.5, display: "progress_only" }),
    );
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenCalledTimes(2));
  });

  it("after saving \"60,5\" the field shows the saved 60.5, says saved and has nothing left to save", async () => {
    const savedProfile = profile({ settings: { body_weight_kg: 60.5, birth_year: null, display: "all" } });
    fetchFitnessProfile.mockResolvedValueOnce(profile()).mockResolvedValue(savedProfile);
    putFitnessSettings.mockResolvedValue(savedProfile.settings);
    renderCard();
    fireEvent.click((await screen.findByTestId("fitness-profile-advanced")).querySelector("button")!);
    const weight = screen.getByLabelText("fitnessBodyWeight");
    fireEvent.change(weight, { target: { value: "60,5" } });
    fireEvent.click(screen.getByRole("button", { name: "fitnessSave" }));
    await waitFor(() => expect(weight).toHaveValue("60.5"));
    expect(await screen.findByRole("status")).toHaveTextContent("fitnessSaved");
    expect(screen.getByRole("button", { name: "fitnessSave" })).toBeDisabled();
  });

  it("an edit made while saving stays when the saved settings come back", async () => {
    const savedProfile = profile({ settings: { body_weight_kg: 60.5, birth_year: null, display: "all" } });
    fetchFitnessProfile.mockResolvedValueOnce(profile()).mockResolvedValue(savedProfile);
    let finish: (value: unknown) => void = () => {};
    putFitnessSettings.mockReturnValue(new Promise((resolve) => (finish = resolve)));
    renderCard();
    fireEvent.click((await screen.findByTestId("fitness-profile-advanced")).querySelector("button")!);
    const weight = screen.getByLabelText("fitnessBodyWeight");
    fireEvent.change(weight, { target: { value: "60,5" } });
    fireEvent.click(screen.getByRole("button", { name: "fitnessSave" }));
    await waitFor(() => expect(putFitnessSettings).toHaveBeenCalled());
    fireEvent.change(weight, { target: { value: "61" } });
    finish(savedProfile.settings);
    await waitFor(() => expect(fetchFitnessProfile).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(screen.getByRole("button", { name: "fitnessSave" })).toBeEnabled());
    expect(weight).toHaveValue("61");
  });

  it("keeps a wrong body weight inside the form, under the field", async () => {
    fetchFitnessProfile.mockResolvedValue(profile());
    renderCard();
    fireEvent.click((await screen.findByTestId("fitness-profile-advanced")).querySelector("button")!);
    const weight = screen.getByLabelText("fitnessBodyWeight");
    fireEvent.change(weight, { target: { value: "12" } });
    fireEvent.click(screen.getByRole("button", { name: "fitnessSave" }));
    expect(await within(screen.getByTestId("fitness-settings")).findByText("fitnessBodyWeightError:25,300")).toBeInTheDocument();
    expect(weight).toHaveAttribute("aria-invalid", "true");
    expect(putFitnessSettings).not.toHaveBeenCalled();
  });

  it("asks for the birth year once the age bands count", async () => {
    fetchFitnessProfile.mockResolvedValue(
      profile({ inputs: { body_weight_kg: null, age_band: null, age_percent: null, age_ready: true } }),
    );
    putFitnessSettings.mockResolvedValue({ body_weight_kg: null, birth_year: 1985, display: "all" });
    renderCard();
    fireEvent.click((await screen.findByTestId("fitness-profile-advanced")).querySelector("button")!);
    fireEvent.change(screen.getByLabelText("fitnessBirthYear"), { target: { value: "1985" } });
    fireEvent.click(screen.getByRole("button", { name: "fitnessSave" }));
    await waitFor(() =>
      expect(putFitnessSettings).toHaveBeenCalledWith("tok", { body_weight_kg: null, birth_year: 1985, display: "all" }),
    );
  });
});
