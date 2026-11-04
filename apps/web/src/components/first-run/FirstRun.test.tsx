import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

const state = vi.hoisted(() => ({
  replace: vi.fn(),
  memberships: [] as unknown[],
  user: { id: "u1", nickname: "Nikos", trains_with_palee: null as boolean | null },
  setTrains: vi.fn(),
  completeTour: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: state.replace }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "tok" }, currentUser: state.user }),
}));
vi.mock("@/lib/membership-role", () => ({
  useOrganizationMemberships: () => ({ data: state.memberships, isSuccess: true }),
}));
vi.mock("@/api/profile", () => ({
  getAvatarUploadUrl: vi.fn(),
  updateAvatar: vi.fn(),
  setTrainsWithPalee: (...args: unknown[]) => state.setTrains(...args),
}));
vi.mock("@/api/onboarding", () => ({ completeProductTour: (...args: unknown[]) => state.completeTour(...args) }));
vi.mock("@/api/organizations", () => ({ redeemInvitation: vi.fn() }));
vi.mock("@/components/interests/InterestsEditor", () => ({
  InterestsEditor: () => <p>interests-editor</p>,
}));
vi.mock("@/components/around/use-around", () => ({ useAroundArea: () => ({ isSuccess: false }) }));
vi.mock("@/components/around/AreaPicker", () => ({ AreaPicker: () => null }));

import { FirstRun } from "./FirstRun";

function renderFirstRun() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <FirstRun />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const coachMembership = {
  role: "coach",
  roles: ["coach"],
  organization: { id: "o1", slug: "thymoa", name: "CrossFit Thymoa" },
};

beforeEach(() => {
  state.replace.mockReset();
  state.setTrains.mockReset();
  state.completeTour.mockReset().mockResolvedValue({ completed_tours: ["first_run"] });
  state.memberships = [];
  state.user = { id: "u1", nickname: "Nikos", trains_with_palee: null };
  window.sessionStorage.clear();
});

describe("FirstRun", () => {
  it("goes from the photo straight to the sports step for a member", () => {
    state.memberships = [{ role: "member", roles: ["member"], organization: { id: "o1", slug: "b", name: "Box" } }];
    renderFirstRun();

    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.skipStep }));

    expect(screen.queryByText(en.FirstRun.athleteTitle)).toBeNull();
    expect(screen.getByRole("heading", { name: en.FirstRun.interestsTitle })).toBeTruthy();
    expect(screen.getByRole("list", { name: "Step 2 of 3" })).toBeTruthy();
  });

  it("asks staff whether they train, naming the role and the box", () => {
    state.memberships = [coachMembership];
    renderFirstRun();

    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.skipStep }));

    expect(screen.getByRole("heading", { name: en.FirstRun.athleteTitle })).toBeTruthy();
    expect(screen.getByText("You joined CrossFit Thymoa as Coach.")).toBeTruthy();
    expect(screen.getByRole("radio", { name: new RegExp(en.FirstRun.athleteYes) }).getAttribute("aria-checked")).toBe("true");
    expect(screen.getByText(en.FirstRun.athleteNote)).toBeTruthy();
    expect(screen.getByRole("list", { name: "Step 2 of 4" })).toBeTruthy();
  });

  it("«No, just for work» saves the answer and finishes", async () => {
    state.memberships = [coachMembership];
    state.setTrains.mockResolvedValue({ trains_with_palee: false });
    renderFirstRun();

    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.skipStep }));
    fireEvent.click(screen.getByRole("radio", { name: new RegExp(en.FirstRun.athleteNo) }));
    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.continue }));

    await waitFor(() => expect(state.replace).toHaveBeenCalledWith("/"));
    expect(state.setTrains).toHaveBeenCalledWith("tok", false);
    expect(state.completeTour).toHaveBeenCalledWith("tok", "first_run");
    expect(screen.queryByText("interests-editor")).toBeNull();
  });

  it("«Yes» saves the answer and goes on to the sports step", async () => {
    state.memberships = [coachMembership];
    state.setTrains.mockResolvedValue({ trains_with_palee: true });
    renderFirstRun();

    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.skipStep }));
    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.continue }));

    expect(await screen.findByText("interests-editor")).toBeTruthy();
    expect(state.setTrains).toHaveBeenCalledWith("tok", true);
    expect(state.replace).not.toHaveBeenCalled();
  });

  it("stays on the question when the answer was not saved", async () => {
    state.memberships = [coachMembership];
    state.setTrains.mockRejectedValue(new Error("offline"));
    renderFirstRun();

    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.skipStep }));
    fireEvent.click(screen.getByRole("radio", { name: new RegExp(en.FirstRun.athleteNo) }));
    fireEvent.click(screen.getByRole("button", { name: en.FirstRun.continue }));

    expect(await screen.findByText(en.FirstRun.saveFailed)).toBeTruthy();
    expect(state.replace).not.toHaveBeenCalled();
  });
});
