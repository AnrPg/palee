import { render, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchMyBoxReviews: vi.fn(), deleteMyBoxReview: vi.fn() }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

import { BoxReviewsSection } from "./BoxReviewsSection";

const membership = { organization: { id: "org-1", name: "CrossFit Κυψέλη", slug: "kypseli" } } as unknown as Parameters<typeof BoxReviewsSection>[0]["membership"];

describe("BoxReviewsSection", () => {
  it("shows nothing, without breaking Box, when the reviews answer is malformed", async () => {
    api.fetchMyBoxReviews.mockResolvedValue({ count: 3, can_review: true });
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const { container } = render(
      <QueryClientProvider client={client}>
        <NextIntlClientProvider locale="el" messages={el}>
          <BoxReviewsSection membership={membership} providerKind="gym" />
        </NextIntlClientProvider>
      </QueryClientProvider>,
    );
    await waitFor(() => expect(api.fetchMyBoxReviews).toHaveBeenCalled());
    expect(container.querySelector("[data-testid=box-reviews]")).toBeNull();
  });
});
