import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ sendSiteForm: vi.fn() }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));

import { formErrors, SiteRequestSheet } from "./SiteRequestSheet";

function wrap(kind: "trial" | "contact" = "trial") {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      <SiteRequestSheet slug="kypseli" kind={kind} privacyHref="/b/kypseli/privacy" onClose={() => undefined} />
    </NextIntlClientProvider>,
  );
}

// ANR s5 A: a sheet from «Κλείσε δοκιμαστικό»; a request becomes a lead, never a booking.
describe("SiteRequestSheet", () => {
  beforeEach(() => api.sendSiteForm.mockReset());

  it("shows each missing field inline and sends nothing", () => {
    wrap();
    fireEvent.click(screen.getByRole("button", { name: "Στείλε το αίτημα" }));
    expect(screen.getByText("Γράψε το όνομά σου.")).toBeTruthy();
    expect(screen.getByText("Γράψε κινητό ή email.")).toBeTruthy();
    expect(screen.getByText("Επιβεβαίωσε ότι διάβασες την πολιτική απορρήτου.")).toBeTruthy();
    expect(api.sendSiteForm).not.toHaveBeenCalled();
  });

  it("sends the request with the contact as email and says it was sent", async () => {
    api.sendSiteForm.mockResolvedValue({ status: "received" });
    wrap();
    fireEvent.change(screen.getByLabelText("Όνομα"), { target: { value: "Ελένη" } });
    fireEvent.change(screen.getByLabelText("Κινητό ή email"), { target: { value: "eleni@example.com" } });
    fireEvent.click(screen.getByRole("checkbox", { name: /πολιτική απορρήτου/ }));
    fireEvent.click(screen.getByRole("button", { name: "Στείλε το αίτημα" }));
    expect(await screen.findByText("Το αίτημα στάλθηκε")).toBeTruthy();
    const [, kind, body] = api.sendSiteForm.mock.calls[0]!;
    expect(kind).toBe("trial");
    expect(body).toMatchObject({ name: "Ελένη", email: "eleni@example.com", privacy_ack: true, marketing_opt_in: false, website: "" });
  });

  it("maps the API's field errors to the form's fields", () => {
    const error = new ApiError(422, "invalid", { errors: { email: ["invalid"], privacy_ack: ["required"] } });
    expect(formErrors(error)).toEqual({ contact: "invalid", privacy_ack: "required" });
    expect(formErrors(new ApiError(422, "invalid", { errors: { phone: ["email_or_phone"] } }))).toEqual({ contact: "required" });
    expect(formErrors(new ApiError(500, "boom", {}))).toBeNull();
  });
});
