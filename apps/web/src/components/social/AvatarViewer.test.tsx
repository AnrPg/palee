import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import Link from "next/link";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { avatarMediaLocked, profileHref } from "./AvatarViewer";
import { PersonAvatar } from "./PersonAvatar";

const api = vi.hoisted(() => ({ fetchPerson: vi.fn(), fetchPersonMedia: vi.fn() }));

vi.mock("next-intl", () => {
  const t = (key: string, values?: Record<string, unknown>) => (values && Object.keys(values).length ? `${key}:${Object.values(values).join(",")}` : key);
  return { useTranslations: () => t };
});
vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/",
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "tok" }, currentUser: { id: "me" } }),
}));
vi.mock("@/api/social", async (importOriginal) => ({ ...(await importOriginal<typeof import("@/api/social")>()), ...api }));

const person = (extra: Record<string, unknown> = {}) => ({ id: "p-1", nickname: "Μαρία", handle: "maria", is_me: false, private: false, my_status: "none", ...extra });
const post = (id: string) => ({ id, media_status: "ready", media: [{ status: "ready", kind: "photo", thumb_url: `https://cdn/${id}.jpg` }] });

function wrap(children: ReactNode) {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>);
}

beforeEach(() => {
  vi.clearAllMocks();
  api.fetchPerson.mockResolvedValue(person());
  api.fetchPersonMedia.mockResolvedValue({ posts: ["a", "b", "c", "d", "e"].map(post), next_cursor: null });
});

describe("PersonAvatar with a person", () => {
  it("is a button on its own and opens the photo with the four newest media, «Προφίλ» and «Όλα τα πολυμέσα»", async () => {
    wrap(<PersonAvatar name="Μαρία" url="https://cdn/maria.jpg" personId="p-1" />);
    fireEvent.click(screen.getByRole("button", { name: "avatarView:Μαρία" }));

    expect(screen.getByRole("dialog", { name: "avatarViewerTitle:Μαρία" })).toBeInTheDocument();
    expect(screen.getByTestId("avatar-viewer-photo")).toHaveAttribute("src", "https://cdn/maria.jpg");
    await waitFor(() => expect(screen.getByTestId("avatar-viewer-strip").querySelectorAll("a")).toHaveLength(4));
    expect(screen.getByTestId("avatar-viewer-strip").querySelector("a")).toHaveAttribute("href", "/people/p-1?tab=media&post=a");
    expect(screen.getByRole("link", { name: "avatarViewerProfile" })).toHaveAttribute("href", "/people/p-1");
    expect(screen.getByRole("link", { name: "avatarViewerAllMedia" })).toHaveAttribute("href", "/people/p-1?tab=media");
    expect(screen.queryByRole("link", { name: "avatarViewerChange" })).not.toBeInTheDocument();
  });

  it("inside a row's link it leaves the link alone: no control in it, the press opens the photo and does not follow the link", () => {
    const followed = vi.fn((event: React.MouseEvent) => event.preventDefault());
    wrap(
      <Link href="/people/p-1" onClick={followed}>
        <PersonAvatar name="Μαρία" url="https://cdn/maria.jpg" personId="p-1" />
        <span>Μαρία</span>
      </Link>,
    );
    expect(screen.getByRole("link")).toHaveAccessibleName("Μαρία");
    expect(screen.queryByRole("button")).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId("avatar-button"));
    expect(followed).not.toHaveBeenCalled();
    expect(screen.getByTestId("avatar-viewer")).toBeInTheDocument();

    // Presses inside the (portalled) viewer never reach the row's link either.
    fireEvent.click(screen.getByTestId("avatar-viewer-photo"));
    expect(followed).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "avatarViewerClose" }));
    expect(screen.queryByTestId("avatar-viewer")).not.toBeInTheDocument();
    fireEvent.click(screen.getByText("Μαρία"));
    expect(followed).toHaveBeenCalledTimes(1);
  });

  it("locks «Πολυμέσα» on a private account you do not follow and loads no media", async () => {
    api.fetchPerson.mockResolvedValue(person({ private: true, my_status: "requested" }));
    wrap(<PersonAvatar name="Ελένη" url="https://cdn/e.jpg" personId="p-1" />);
    fireEvent.click(screen.getByRole("button", { name: "avatarView:Ελένη" }));

    await waitFor(() => expect(screen.getByTestId("avatar-viewer-locked")).toHaveTextContent("avatarViewerLocked"));
    expect(screen.getByRole("button", { name: "avatarViewerMedia" })).toBeDisabled();
    expect(api.fetchPersonMedia).not.toHaveBeenCalled();
  });

  it("on the profile itself offers only «Πολυμέσα», and on your own photo «Αλλαγή φωτογραφίας»", async () => {
    api.fetchPerson.mockResolvedValue(person({ is_me: true }));
    wrap(<PersonAvatar name="Εγώ" url="https://cdn/me.jpg" personId="p-1" onProfile />);
    fireEvent.click(screen.getByRole("button", { name: "avatarView:Εγώ" }));

    await waitFor(() => expect(screen.getByRole("link", { name: "avatarViewerChange" })).toHaveAttribute("href", "/me/settings#avatar"));
    expect(screen.queryByRole("link", { name: "avatarViewerProfile" })).not.toBeInTheDocument();
    expect(await screen.findByRole("link", { name: "avatarViewerAllMedia" })).toHaveAttribute("href", "/me?tab=media");
  });

  it("keeps initials and photos without a person as they were", () => {
    wrap(
      <>
        <PersonAvatar name="Νίκος Δ" personId="p-2" />
        <PersonAvatar name="Box" url="https://cdn/logo.jpg" />
      </>,
    );
    expect(screen.queryByTestId("avatar-button")).not.toBeInTheDocument();
    expect(screen.getByText("ΝΔ")).toBeInTheDocument();
  });
});

describe("avatar viewer rules", () => {
  it("locks media only for a private account you do not follow", () => {
    expect(avatarMediaLocked(person({ private: true, my_status: "none" }))).toBe(true);
    expect(avatarMediaLocked(person({ private: true, my_status: "active" }))).toBe(false);
    expect(avatarMediaLocked(person({ private: true, is_me: true }))).toBe(false);
    expect(avatarMediaLocked(person({ private: false }))).toBe(false);
    expect(avatarMediaLocked(undefined)).toBe(false);
  });

  it("sends you to Εγώ for your own profile", () => {
    expect(profileHref("p-1", true, "?tab=media")).toBe("/me?tab=media");
    expect(profileHref("p-1", false)).toBe("/people/p-1");
  });
});
