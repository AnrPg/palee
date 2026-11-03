import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const replace = vi.fn();
let membershipsQuery: { isSuccess: boolean; data: unknown };

vi.mock("next/navigation", () => ({ usePathname: () => "/", useRouter: () => ({ replace }) }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ currentUser: { id: "u1", vendor: false, completed_tours: ["first_run"] } }) }));
vi.mock("@/lib/first-run", () => ({ needsFirstRun: () => false }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationMemberships: () => membershipsQuery }));
vi.mock("@/components/member-app/HomeHub", () => ({ HomeHub: () => null }));
vi.mock("@/components/platform/PlatformOrganizationsPage", () => ({ PlatformOrganizationsPage: () => null }));

import { resetAppOpenLanding } from "@/lib/app-open-landing";

import { Home } from "./home";

// W7 screen 12: one box opens on Box; the decision waits for the memberships.
describe("Home app-open landing", () => {
  beforeEach(() => {
    replace.mockClear();
    resetAppOpenLanding();
  });

  it("waits while the memberships are not loaded, then opens a one-box member on Box", () => {
    membershipsQuery = { isSuccess: false, data: undefined };
    const { rerender } = render(<Home />);
    expect(replace).not.toHaveBeenCalled();

    membershipsQuery = { isSuccess: true, data: [{ organization: { slug: "box1" } }] };
    rerender(<Home />);
    expect(replace).toHaveBeenCalledWith("/box");
  });

  it("stays on Feed with two boxes", () => {
    membershipsQuery = { isSuccess: true, data: [{}, {}] };
    render(<Home />);
    expect(replace).not.toHaveBeenCalled();
  });
});
