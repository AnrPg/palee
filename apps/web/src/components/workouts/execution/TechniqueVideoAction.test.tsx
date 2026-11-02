import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { TechniqueVideoAction } from "./TechniqueVideoAction";

let entitlement: unknown = null;

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/components/client/use-client-entitlement", () => ({
  CLIENT_ENTITLEMENT_QUERY_KEY: ["client", "entitlement"],
  useClientEntitlement: () => ({ entitlement }),
}));
vi.mock("@/components/client/CoachingConsole", () => ({
  FORM_REVIEWS_KEY: ["form-reviews"],
  FormReviewForm: ({ executionId, onSubmitted }: { executionId: string; onSubmitted: () => void }) => (
    <button type="button" onClick={onSubmitted}>
      send for {executionId}
    </button>
  ),
}));

function renderAction() {
  const client = new QueryClient();
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<TechniqueVideoAction executionId="x1" />, { wrapper });
}

const withVideos = (remaining: number | "unlimited") => ({
  plan: { capabilities: ["request_form_reviews"] },
  allowances: { form_reviews: { remaining, limit: 4 } },
});

describe("TechniqueVideoAction (mockup d5 A)", () => {
  beforeEach(() => {
    entitlement = null;
  });

  it("is not there without technique videos in the package", () => {
    const { container } = renderAction();
    expect(container).toBeEmptyDOMElement();
  });

  it("is not there once the videos are used up", () => {
    entitlement = withVideos(0);
    const { container } = renderAction();
    expect(container).toBeEmptyDOMElement();
  });

  it("sends a video tied to this run and says it went", () => {
    entitlement = withVideos(2);
    renderAction();
    expect(screen.getByText("videoLeft:2")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("technique-video"));
    fireEvent.click(screen.getByRole("button", { name: "send for x1" }));
    expect(screen.getByRole("status")).toHaveTextContent("videoSent");
  });
});
