import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import type { BoxSearchResult } from "@/api/social";

import { BoxResultRow } from "./BoxSearch";
import { JoinBoxButton } from "./JoinBoxButton";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "access" } }) }));

function wrap(node: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, enabled: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        {node}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("JoinBoxButton (ADR-638)", () => {
  it("offers «Γίνε μέλος» in Spark, starting the box page's join flow", () => {
    wrap(<JoinBoxButton slug="milos method" status="none" />);
    const link = screen.getByTestId("join-box");
    expect(link).toHaveTextContent("Γίνε μέλος");
    expect(link).toHaveAttribute("href", "/b/milos%20method?join=1");
    expect(link.getAttribute("style")).toContain("var(--spark)");
  });

  it("shows a waiting request quietly", () => {
    wrap(<JoinBoxButton slug="kypseli" status="requested" />);
    const link = screen.getByTestId("join-box");
    expect(link).toHaveTextContent("Αίτημα εστάλη");
    expect(link.getAttribute("style")).not.toContain("var(--spark)");
  });

  it.each(["member", "staff"] as const)("shows nothing to the box's %s", (status) => {
    wrap(<JoinBoxButton slug="kypseli" status={status} />);
    expect(screen.queryByTestId("join-box")).toBeNull();
  });
});

describe("BoxResultRow (ADR-638)", () => {
  const box = (my_join: BoxSearchResult["my_join"]): BoxSearchResult => ({
    organization_id: "org-1",
    slug: "kypseli",
    name: "Box Κυψέλη",
    provider_kind: "coach",
    my_status: "none",
    my_join,
  });

  it("puts «Γίνε μέλος» first and an outlined «Ακολούθησε» beside it", () => {
    wrap(<ul><BoxResultRow box={box("none")} /></ul>);
    const join = screen.getByTestId("join-box");
    const follow = screen.getByRole("button", { name: "Ακολούθησε" });
    expect(join.compareDocumentPosition(follow) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(follow.getAttribute("style")).not.toContain("var(--primary)");
  });

  it("a member sees «Αθλητής» (coach) instead of «Γίνε μέλος», and an outlined «Ακολούθησε»", () => {
    wrap(<ul><BoxResultRow box={box("member")} /></ul>);
    expect(screen.queryByTestId("join-box")).toBeNull();
    expect(screen.getByTestId("box-relation").textContent).toBe("Αθλητής");
    expect(screen.getByRole("button", { name: "Ακολούθησε" }).getAttribute("style")).not.toContain("var(--primary)");
  });

  it("says «Μέλος box» or «Staff του box» for a box, and nothing to someone who may join", () => {
    wrap(<ul><BoxResultRow box={{ ...box("member"), provider_kind: "gym" }} /><BoxResultRow box={{ ...box("staff"), provider_kind: "gym", organization_id: "org-2" }} /><BoxResultRow box={{ ...box("none"), organization_id: "org-3" }} /></ul>);
    expect(screen.getAllByTestId("box-relation").map((chip) => chip.textContent)).toEqual(["Μέλος box", "Staff του box"]);
  });
});
