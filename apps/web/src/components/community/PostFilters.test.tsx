import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import type { CommunityClub } from "@/api/community";
import { emptyListFilter } from "@/components/filters/list-filter";

import en from "../../../messages/en.json";

import { CLUB_POSTS_SHAPE, PostFilters } from "./PostFilters";

const channel = (id: string, kind: "general" | "wod") => ({
  id,
  kind,
  name: null,
  write_policy: "members" as const,
  membership: "everyone" as const,
  joined: true,
  can_post: true,
  can_leave: false,
});

const club = {
  id: "club-1",
  kind: "gym",
  name: "Box Kypseli",
  organization_id: "org-1",
  organization_slug: "kypseli",
  box_page: true,
  role: "member",
  notify_level: "all",
  channels: [channel("ch-gen", "general"), channel("ch-wod", "wod")],
} as unknown as CommunityClub;

function filters(channelChip?: boolean) {
  render(
    <NextIntlClientProvider locale="en" messages={en}>
      <PostFilters shape={CLUB_POSTS_SHAPE} filter={emptyListFilter(CLUB_POSTS_SHAPE)} onChange={vi.fn()} clubs={[club]} clubId={club.id} channelChip={channelChip} />
    </NextIntlClientProvider>,
  );
}

// ADR-621: «Posts by coaches» narrows to posts written by coaches; it lives in the sheet only.
describe("PostFilters", () => {
  it("keeps the coaches filter out of the chip row, under its clear name in the sheet", () => {
    filters();
    expect(screen.queryByRole("button", { name: "Posts by coaches" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Coaches only" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Filters" }));
    expect(screen.getByRole("dialog", { name: "Post filters" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Posts by coaches" })).toBeTruthy();
  });

  it("shows the channel as a chip on the club page, and only in the sheet on the box page", () => {
    filters();
    expect(screen.getAllByText("Channel").length).toBeGreaterThan(0);
  });

  it("box page: no channel chip in the row", () => {
    filters(false);
    expect(screen.queryByText("Channel")).toBeNull();
  });
});
