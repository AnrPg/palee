import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { EnquiryCard, LeadEnquiryForm } from "./LeadEnquiryForm";

const state = vi.hoisted(() => ({ sendEnquiry: vi.fn(), status: "unauthenticated" }));

vi.mock("@/api/leads", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/leads")>()),
  sendEnquiry: state.sendEnquiry,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: state.status }),
}));

function renderWith(ui: React.ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  state.sendEnquiry.mockReset();
  state.status = "unauthenticated";
});

describe("LeadEnquiryForm", () => {
  it("keeps errors in the form, under each field, and sends nothing", () => {
    renderWith(<LeadEnquiryForm slug="crossfit-x" boxName="CrossFit X" onClose={() => {}} />);
    fireEvent.click(screen.getByTestId("enquiry-send"));
    expect(screen.getByText(en.LeadEnquiry.nameRequired)).toBeTruthy();
    expect(screen.getByText(en.LeadEnquiry.contactRequired)).toBeTruthy();
    expect(screen.getByText(en.LeadEnquiry.consentRequired)).toBeTruthy();
    expect(screen.getByLabelText(new RegExp(en.LeadEnquiry.name)).getAttribute("aria-invalid")).toBe("true");
    expect(state.sendEnquiry).not.toHaveBeenCalled();
  });

  it("sends a phone enquiry with the consent and shows the thank-you", async () => {
    state.sendEnquiry.mockResolvedValue({});
    renderWith(<LeadEnquiryForm slug="crossfit-x" boxName="CrossFit X" onClose={() => {}} />);
    fireEvent.change(screen.getByLabelText(new RegExp(en.LeadEnquiry.name)), { target: { value: "Anna" } });
    fireEvent.change(screen.getByLabelText(new RegExp(en.LeadEnquiry.contact)), { target: { value: "6900000000" } });
    fireEvent.click(screen.getByRole("button", { name: en.LeadEnquiry.interestOption.trial }));
    fireEvent.click(screen.getByTestId("enquiry-consent"));
    fireEvent.click(screen.getByTestId("enquiry-send"));
    await waitFor(() => expect(screen.getByTestId("enquiry-sent")).toBeTruthy());
    const [slug, body] = state.sendEnquiry.mock.calls[0];
    expect(slug).toBe("crossfit-x");
    expect(body).toMatchObject({
      name: "Anna",
      phone: "6900000000",
      interests: ["trial"],
      kind: "trial",
      consent: { contact: true, marketing: false },
      website: "",
    });
  });
});

describe("EnquiryCard", () => {
  it("is shown only to visitors who are not signed in", () => {
    const { rerender } = renderWith(<EnquiryCard slug="crossfit-x" boxName="CrossFit X" />);
    expect(screen.getByTestId("enquiry-open")).toBeTruthy();
    state.status = "authenticated";
    rerender(
      <QueryClientProvider client={new QueryClient()}>
        <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
          <EnquiryCard slug="crossfit-x" boxName="CrossFit X" />
        </NextIntlClientProvider>
      </QueryClientProvider>,
    );
    expect(screen.queryByTestId("enquiry-open")).toBeNull();
  });
});
