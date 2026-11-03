import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { WorkoutBenchmarkPicker } from "./WorkoutBenchmarkPicker";

const fetchWorkoutBenchmarks = vi.fn();
const setWorkoutBenchmark = vi.fn();

vi.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/workouts", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/workouts")>()),
  fetchWorkoutBenchmarks: (...args: unknown[]) => fetchWorkoutBenchmarks(...args),
  setWorkoutBenchmark: (...args: unknown[]) => setWorkoutBenchmark(...args),
}));

function renderPicker(initialKey: string | null = null) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<WorkoutBenchmarkPicker workoutId="w1" initialKey={initialKey} />, { wrapper });
}

describe("WorkoutBenchmarkPicker (ADR-394)", () => {
  beforeEach(() => {
    fetchWorkoutBenchmarks.mockReset().mockResolvedValue({
      benchmarks: [
        { key: "fran", group: "metcon", unit: "mins_secs", lower_is_better: true },
        { key: "murph", group: "metcon", unit: "mins_secs", lower_is_better: true },
        { key: "back_squat", group: "strength", unit: "kg", lower_is_better: false },
      ],
    });
    setWorkoutBenchmark.mockReset();
  });

  it("sits under «Προχωρημένα», closed by default", () => {
    renderPicker();
    expect(screen.getByTestId("workout-benchmark-advanced")).toBeInTheDocument();
    expect(screen.queryByText("benchmarkPickerTitle")).toBeNull();
  });

  it("the coach picks a benchmark from the list and it is saved at once", async () => {
    setWorkoutBenchmark.mockResolvedValue({ id: "w1", benchmark: { key: "fran", group: "metcon", unit: "mins_secs", lower_is_better: true } });
    renderPicker();
    fireEvent.click(screen.getByRole("button", { expanded: false }));
    const select = await screen.findByLabelText("benchmarkPickerTitle");
    await waitFor(() => expect(select).not.toBeDisabled());
    expect(select).toHaveTextContent("benchmarkNone");
    fireEvent.click(select);
    fireEvent.click(await screen.findByRole("option", { name: "benchmark_fran" }));
    await waitFor(() => expect(setWorkoutBenchmark).toHaveBeenCalledWith("tok", "w1", "fran"));
    await waitFor(() => expect(screen.getByLabelText("benchmarkPickerTitle")).toHaveTextContent("benchmark_fran"));
  });

  it("«Όχι benchmark» clears the tag", async () => {
    setWorkoutBenchmark.mockResolvedValue({ id: "w1", benchmark: null });
    renderPicker("murph");
    fireEvent.click(screen.getByRole("button", { expanded: false }));
    const select = await screen.findByLabelText("benchmarkPickerTitle");
    await waitFor(() => expect(select).toHaveTextContent("benchmark_murph"));
    fireEvent.click(select);
    fireEvent.click(await screen.findByRole("option", { name: "benchmarkNone" }));
    await waitFor(() => expect(setWorkoutBenchmark).toHaveBeenCalledWith("tok", "w1", null));
  });
});
