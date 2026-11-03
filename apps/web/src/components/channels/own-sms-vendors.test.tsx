import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { ApiError } from "@/api/client";
import type { ChannelConnection, ChannelSettings } from "@/api/channels";

import { SmsConnectionSettings } from "./SmsConnectionSettings";

/*
 * ADR-396: the box's own SMS vendor under «Advanced» — the vendor picker,
 * each vendor's guide and fields, and errors that stay in the form.
 */

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/api/channels", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/channels")>()),
  fetchChannelSettings: vi.fn(),
  saveChannelSettings: vi.fn(),
  checkChannelSettings: vi.fn(),
  fetchChannelTemplates: vi.fn(),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ membership: { organization: { name: "Box Kypseli", activation: "active" }, settings: null } }),
}));
vi.mock("@/components/channels/OwnEmailSettings", () => ({ OwnEmailSettings: () => null }));

const channels = await import("@/api/channels");

const SID = `AC${"0a".repeat(16)}`;
const usage = { from: "", to: "", spent_cents: 0, messages: 0, by_channel: {}, currency: "EUR", palee_charge_cents: 0 };
const providers = [
  { provider: "brevo", channels: ["sms" as const], account_modes: ["own", "palee"] },
  ...["twilio", "vonage", "infobip", "yuboto", "apifon"].map((provider) => ({ provider, channels: ["sms" as const], account_modes: ["own"] })),
  { provider: "sandbox", channels: ["sms" as const], account_modes: ["own", "palee"] },
];
const connection: ChannelConnection = {
  provider: "brevo",
  account_mode: "palee",
  channels: ["sms"],
  channel_order: ["sms"],
  default_country: "GR",
  has_secret: false,
  monthly_budget_cents: 1500,
  quiet_start: null,
  quiet_end: null,
  status: "active",
  currency: "EUR",
};

type SaveResult = Awaited<ReturnType<typeof channels.saveChannelSettings>>;

function wrap(children: ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

async function openOwnAccount(settings: ChannelSettings) {
  vi.mocked(channels.fetchChannelSettings).mockResolvedValue(settings);
  wrap(<SmsConnectionSettings token="t" />);
  fireEvent.click(await screen.findByRole("button", { name: /Advanced/ }));
  return screen.findByTestId("sms-own-account");
}

async function pickVendor(section: HTMLElement, name: string) {
  fireEvent.click(within(section).getByLabelText("SMS provider"));
  fireEvent.click(await screen.findByRole("option", { name }));
}

describe("own SMS vendor (ADR-396)", () => {
  beforeEach(() => {
    vi.mocked(channels.saveChannelSettings).mockReset();
    vi.mocked(channels.fetchChannelTemplates).mockResolvedValue({ templates: [] } as unknown as Awaited<ReturnType<typeof channels.fetchChannelTemplates>>);
  });

  it("offers every vendor with its own guide and fields, Brevo first", async () => {
    const section = await openOwnAccount({ connection, providers, usage });
    fireEvent.click(within(section).getByRole("button", { name: "Use my own SMS provider" }));

    expect(within(section).getByTestId("brevo-guide").querySelectorAll("li")).toHaveLength(4);
    expect(within(section).getByLabelText("Brevo API key")).toBeTruthy();

    fireEvent.click(within(section).getByLabelText("SMS provider"));
    const names = (await screen.findAllByRole("option")).map((option) => option.textContent);
    expect(names).toEqual(["Brevo", "Twilio", "Vonage", "Infobip", "Yuboto", "Apifon"]);
    fireEvent.click(screen.getByRole("option", { name: "Vonage" }));

    expect(within(section).getByTestId("vonage-guide").textContent).toContain("dashboard.nexmo.com");
    expect(within(section).getByLabelText("API key")).toBeTruthy();
    expect((within(section).getByLabelText("API secret") as HTMLInputElement).type).toBe("password");
    expect(within(section).getByLabelText("Signature secret")).toBeTruthy();
    expect(within(section).getByText(en.Sms.vonageSignatureHint)).toBeTruthy();

    await pickVendor(section, "Infobip");
    expect(within(section).getByTestId("infobip-guide").textContent).toContain("Base URL");
    expect(within(section).getByLabelText("Base URL")).toBeTruthy();
  });

  it("says what is missing or wrong under each field before anything is sent", async () => {
    const section = await openOwnAccount({ connection, providers, usage });
    fireEvent.click(within(section).getByRole("button", { name: "Use my own SMS provider" }));
    await pickVendor(section, "Twilio");

    fireEvent.click(within(section).getByRole("button", { name: "Save key" }));
    const sid = within(section).getByLabelText("Account SID");
    const token = within(section).getByLabelText("Auth Token");
    expect(sid.getAttribute("aria-invalid")).toBe("true");
    expect(token.getAttribute("aria-invalid")).toBe("true");
    expect(within(section).getAllByText("Fill this in.")).toHaveLength(2);

    fireEvent.change(sid, { target: { value: "AC123" } });
    fireEvent.change(token, { target: { value: "tw-token" } });
    expect(within(section).getByText("The Account SID starts with AC and has 34 characters.")).toBeTruthy();
    expect(channels.saveChannelSettings).not.toHaveBeenCalled();

    vi.mocked(channels.saveChannelSettings).mockResolvedValue({
      connection: { ...connection, provider: "twilio", account_mode: "own", account_id: SID, has_secret: true },
      check: { ok: true, details: {} },
    } as unknown as SaveResult);
    fireEvent.change(sid, { target: { value: SID } });
    fireEvent.click(within(section).getByRole("button", { name: "Save key" }));

    await waitFor(() => expect(channels.saveChannelSettings).toHaveBeenCalled());
    expect(vi.mocked(channels.saveChannelSettings).mock.calls[0][1]).toEqual({ provider: "twilio", account_mode: "own", account_id: SID, secret: "tw-token" });
    expect(await screen.findByText("Your own Twilio account")).toBeTruthy();
  });

  it("keeps the form open when the vendor refuses the key", async () => {
    vi.mocked(channels.saveChannelSettings).mockResolvedValue({
      connection: { ...connection, provider: "yuboto", account_mode: "own", has_secret: true, status: "invalid" },
      check: { ok: false, error_code: "credentials_rejected", details: {} },
    } as unknown as SaveResult);
    const section = await openOwnAccount({ connection, providers, usage });
    fireEvent.click(within(section).getByRole("button", { name: "Use my own SMS provider" }));
    await pickVendor(section, "Yuboto");

    expect(within(section).getByTestId("yuboto-guide").textContent).toContain("octapush.yuboto.com");
    fireEvent.change(within(section).getByLabelText("OMNI API key"), { target: { value: "bad" } });
    fireEvent.click(within(section).getByRole("button", { name: "Save key" }));

    expect(await within(section).findByText("Yuboto did not accept these details.")).toBeTruthy();
    expect(within(section).getByLabelText("OMNI API key").getAttribute("aria-invalid")).toBe("true");
  });

  it("shows the API's field reason under that field", async () => {
    vi.mocked(channels.saveChannelSettings).mockRejectedValue(
      new ApiError(422, "validation_failed", { code: "validation_failed", errors: { base_url: ["invalid"] } } as unknown as ConstructorParameters<typeof ApiError>[2]),
    );
    const section = await openOwnAccount({ connection, providers, usage });
    fireEvent.click(within(section).getByRole("button", { name: "Use my own SMS provider" }));
    await pickVendor(section, "Infobip");

    fireEvent.change(within(section).getByLabelText("Base URL"), { target: { value: "https://ab12.api.infobip.com" } });
    fireEvent.change(within(section).getByLabelText("API key"), { target: { value: "ib-key" } });
    fireEvent.click(within(section).getByRole("button", { name: "Save key" }));

    expect(await within(section).findByText(en.Sms.infobipBaseUrlInvalid)).toBeTruthy();
    expect(vi.mocked(channels.saveChannelSettings).mock.calls[0][1]).toEqual({
      provider: "infobip",
      account_mode: "own",
      base_url: "https://ab12.api.infobip.com",
      secret: "ib-key",
    });
  });

  it("an own vendor keeps its saved key, and «Back to Palee's account» goes back to Brevo", async () => {
    const own = { ...connection, provider: "apifon", account_mode: "own" as const, account_id: "ap-token", has_secret: true };
    vi.mocked(channels.saveChannelSettings)
      .mockResolvedValueOnce({ connection: own, check: { ok: true, details: {} } } as unknown as SaveResult)
      .mockResolvedValueOnce({ connection, check: { ok: true, details: {} } } as unknown as SaveResult);
    const section = await openOwnAccount({ connection: own, providers, usage });

    expect(screen.getByText("Your own Apifon account")).toBeTruthy();
    fireEvent.click(within(section).getByRole("button", { name: "Replace the key" }));
    expect((within(section).getByLabelText("API token") as HTMLInputElement).value).toBe("ap-token");
    expect(within(section).getByLabelText("Secret key").getAttribute("placeholder")).toBe(en.Sms.vendorSecretKept);
    fireEvent.click(within(section).getByRole("button", { name: "Save key" }));
    await waitFor(() => expect(channels.saveChannelSettings).toHaveBeenCalledTimes(1));
    expect(vi.mocked(channels.saveChannelSettings).mock.calls[0][1]).toEqual({ provider: "apifon", account_mode: "own", account_id: "ap-token" });

    fireEvent.click(await within(section).findByRole("button", { name: "Back to Palee's account" }));
    await waitFor(() => expect(channels.saveChannelSettings).toHaveBeenCalledTimes(2));
    expect(vi.mocked(channels.saveChannelSettings).mock.calls[1][1]).toEqual({ provider: "brevo", account_mode: "palee" });
  });

  it("with Twilio the sender field takes a Messaging Service SID, with its reason in the form", async () => {
    const twilio = { ...connection, provider: "twilio", account_mode: "own" as const, account_id: SID, has_secret: true, sms_sender: "CFAthina" };
    vi.mocked(channels.fetchChannelSettings).mockResolvedValue({ connection: twilio, providers, usage });
    vi.mocked(channels.saveChannelSettings).mockResolvedValue({ connection: twilio, check: { ok: true, details: {} } } as unknown as SaveResult);
    wrap(<SmsConnectionSettings token="t" />);

    const sender = await screen.findByLabelText("Sender");
    expect(screen.getByText(en.Sms.senderHintTwilio)).toBeTruthy();
    fireEvent.change(sender, { target: { value: `MG${"zz".repeat(16)}` } });
    expect(screen.getByText(en.Sms.sender_twilioService)).toBeTruthy();
    expect(sender.getAttribute("aria-invalid")).toBe("true");

    const service = `MG${"0f".repeat(16)}`;
    fireEvent.change(sender, { target: { value: service } });
    expect(sender.getAttribute("aria-invalid")).toBe("false");
    fireEvent.click(screen.getByRole("button", { name: en.Sms.saveSender }));
    await waitFor(() => expect(channels.saveChannelSettings).toHaveBeenCalled());
    expect(vi.mocked(channels.saveChannelSettings).mock.calls[0][1]).toMatchObject({ sms_sender: service });
  });
});
