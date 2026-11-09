import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { FollowSuggestion } from "@/api/follow-suggestions";

import { FindFollowSuggestions } from "./FollowSuggestions";

const api = vi.hoisted(() => ({
  fetchFollowSuggestions: vi.fn(),
  followSuggested: vi.fn(),
  dismissSuggestion: vi.fn(),
  undismissSuggestion: vi.fn(),
}));

vi.mock("next-intl", () => {
  const t = Object.assign((key: string, values?: Record<string, unknown>) => (values && Object.keys(values).length ? `${key}:${Object.values(values).join(",")}` : key), {
    has: (key: string) => key === "discipline.crossfit",
  });
  return { useTranslations: () => t };
});
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "tok" }, currentUser: { id: "me" } }),
}));
vi.mock("@/api/follow-suggestions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/follow-suggestions")>()),
  ...api,
}));

const people: FollowSuggestion[] = [
  {
    id: "p-1",
    nickname: "Μαρία",
    handle: "maria",
    avatar_url: null,
    private: false,
    reason: { kind: "box", box: { id: "b", name: "Milos method" }, mutual_count: 0, mutuals: [] },
  },
  {
    id: "p-2",
    nickname: "Κώστας",
    handle: null,
    avatar_url: null,
    private: true,
    reason: { kind: "follows_you", mutual_count: 0, mutuals: [] },
  },
];

function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>;
}

describe("FindFollowSuggestions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.fetchFollowSuggestions.mockResolvedValue({ people });
    api.followSuggested.mockResolvedValue("active");
    api.dismissSuggestion.mockResolvedValue(undefined);
    api.undismissSuggestion.mockResolvedValue(undefined);
  });

  it("lists each person with one reason and follows through the suggestion", async () => {
    render(<FindFollowSuggestions />, { wrapper });
    expect(await screen.findByText("reason.box:Milos method")).toBeTruthy();
    expect(screen.getByText("reason.followsYou")).toBeTruthy();
    // Someone who follows you is offered «follow back».
    expect(screen.getByRole("button", { name: "followBack" })).toBeTruthy();

    fireEvent.click(screen.getAllByRole("button", { name: "follow" })[0]);
    await waitFor(() => expect(api.followSuggested).toHaveBeenCalledWith("tok", "p-1", "box"));
    expect(await screen.findByText("following")).toBeTruthy();
  });

  it("✕ removes a person in place and «Αναίρεση» brings them back", async () => {
    render(<FindFollowSuggestions />, { wrapper });
    fireEvent.click(await screen.findByRole("button", { name: "dismiss:Μαρία" }));
    expect(await screen.findByText("dismissed")).toBeTruthy();
    expect(api.dismissSuggestion).toHaveBeenCalledWith("tok", "p-1", "box");

    fireEvent.click(screen.getByRole("button", { name: "undo" }));
    expect(await screen.findByText("reason.box:Milos method")).toBeTruthy();
    expect(api.undismissSuggestion).toHaveBeenCalledWith("tok", "p-1");
  });

  it("shows nothing when there is nobody to suggest", async () => {
    api.fetchFollowSuggestions.mockResolvedValue({ people: [] });
    const { container } = render(<FindFollowSuggestions />, { wrapper });
    await waitFor(() => expect(api.fetchFollowSuggestions).toHaveBeenCalled());
    expect(container.querySelector("[data-follow-suggestions]")).toBeNull();
  });
});
