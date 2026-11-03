import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { WodAsPerformed } from "./WodAsPerformed";

const fetchWorkoutAsPerformed = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    memberships: [{ organization: { id: "org", slug: "box", timezone: "Europe/Athens" } }],
  }),
}));
vi.mock("@/api/training-floor", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/training-floor")>()),
  fetchWorkoutAsPerformed: (...args: unknown[]) => fetchWorkoutAsPerformed(...args),
}));

const snapshot = {
  id: "s1",
  workout_id: "w1",
  title: "Fran",
  taken_at: "2026-11-02T05:30:00Z",
  content_hash: "h",
  format_version: 1,
  content: { content: "21-15-9\nThrusters 43 kg" },
};

function renderLine(organizationId: string | null = "org") {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<WodAsPerformed organizationId={organizationId} kind="training_log" id="e1" />, { wrapper });
}

describe("WodAsPerformed (ADR-357/389, mockup d3 A)", () => {
  beforeEach(() => fetchWorkoutAsPerformed.mockReset());

  it("shows nothing while the WOD is the same", async () => {
    fetchWorkoutAsPerformed.mockResolvedValue({ snapshot, changed: false });
    const { container } = renderLine();
    await waitFor(() => expect(fetchWorkoutAsPerformed).toHaveBeenCalledWith("tok", "box", "training_log", "e1"));
    expect(container).toBeEmptyDOMElement();
  });

  it("after a change, opens the WOD as it was, on the box's 24h clock", async () => {
    fetchWorkoutAsPerformed.mockResolvedValue({ snapshot, changed: true });
    renderLine();
    const line = await screen.findByTestId("wod-changed-e1");
    expect(line).toHaveTextContent("snapshotChanged");
    // 05:30Z is 07:30 in Athens.
    expect(line).toHaveTextContent("07:30");
    fireEvent.click(line.querySelector("button")!);
    expect(await screen.findByRole("dialog")).toHaveTextContent("Fran");
    expect(screen.getByTestId("wod-snapshot-lines")).toHaveTextContent("Thrusters 43 kg");
  });

  it("does not ask without a box it knows", () => {
    renderLine(null);
    expect(fetchWorkoutAsPerformed).not.toHaveBeenCalled();
  });
});
