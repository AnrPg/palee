import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import en from "../../../../messages/en.json";

import { ApiError } from "@/api/client";
import { fetchClientFitnessDisplay, saveClientFitnessDisplay, type ClientFitnessDisplay } from "@/api/staff";
import { ClientFitnessDisplayPanel } from "./ClientFitnessDisplayPanel";
import { clientChoiceWins, coachChoice, overrideFor, personalFacts, showsClientFitnessDisplay } from "./client-fitness-display";
import { SECTION_TAB } from "./member-profile-tabs";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "coach-1" }, status: "authenticated" }),
}));
vi.mock("@/api/staff", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/staff")>()),
  fetchClientFitnessDisplay: vi.fn(),
  saveClientFitnessDisplay: vi.fn(),
}));

const client = "client-1";
const view = (settings: ClientFitnessDisplay["settings"], override: ClientFitnessDisplay["override"] = null): ClientFitnessDisplay => ({
  settings,
  override,
});
const filled = view({ body_weight_kg: 72.5, birth_year: 1988, display: "all" });
const notYourClient = () => new ApiError(403, "Not one of your clients", { code: "not_your_client" } as never);

function renderPanel(locale: "en" | "el" = "en") {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : el}>
        <ClientFitnessDisplayPanel
          userId={client}
          nickname="Maria"
          frame={(content: ReactNode) => <section data-testid="fitness-display-frame">{content}</section>}
        />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const choice = (name: string) => screen.getByRole("radio", { name });
const save = () => fireEvent.click(screen.getByTestId("client-fitness-display-save-bar-save"));

beforeEach(() => {
  vi.clearAllMocks();
});

describe("who sees the client's fitness card panel", () => {
  it("is in the training tab, only on a client's profile and only for a coach who may read client training", () => {
    expect(SECTION_TAB.fitness_display).toBe("training");
    expect(showsClientFitnessDisplay({ isClient: true, actorCoaches: true, canViewClientTraining: true })).toBe(true);
    expect(showsClientFitnessDisplay({ isClient: false, actorCoaches: true, canViewClientTraining: true })).toBe(false);
    expect(showsClientFitnessDisplay({ isClient: true, actorCoaches: false, canViewClientTraining: true })).toBe(false);
    expect(showsClientFitnessDisplay({ isClient: true, actorCoaches: true, canViewClientTraining: false })).toBe(false);
  });

  it("shows nothing, not even the frame, to staff who do not coach the client (403 not_your_client)", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockRejectedValue(notYourClient());
    renderPanel();

    await waitFor(() => expect(fetchClientFitnessDisplay).toHaveBeenCalledWith("access", client));
    await waitFor(() => expect(screen.queryByTestId("fitness-display-frame")).not.toBeInTheDocument());
    expect(screen.queryByText(/72/)).not.toBeInTheDocument();
    expect(screen.queryByText(/not one of your clients/i)).not.toBeInTheDocument();
  });

  it("shows another failure inside the panel", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockRejectedValue(new ApiError(500, "boom", { code: "internal" } as never));
    renderPanel();

    const frame = await screen.findByTestId("fitness-display-frame");
    expect(within(frame).getByRole("alert")).toBeInTheDocument();
  });
});

describe("the client's body weight and birth year", () => {
  it("are shown read-only", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(filled);
    renderPanel();

    const facts = await screen.findByTestId("client-fitness-facts");
    expect(within(facts).getByText("72.5 kg")).toBeInTheDocument();
    expect(within(facts).getByText("1988")).toBeInTheDocument();
    expect(within(facts).queryByRole("textbox")).not.toBeInTheDocument();
    expect(within(facts).queryByRole("spinbutton")).not.toBeInTheDocument();
  });

  it("say «not filled in» for the one missing", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view({ body_weight_kg: null, birth_year: 1990, display: "all" }));
    renderPanel();

    const facts = await screen.findByTestId("client-fitness-facts");
    expect(within(facts).getByText("not filled in")).toBeInTheDocument();
    expect(within(facts).getByText("1990")).toBeInTheDocument();
  });

  it("are one plain line in Greek when the client set nothing", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view(null));
    renderPanel("el");

    expect(await screen.findByText("Ο/Η Maria δεν έχει συμπληρώσει βάρος σώματος και έτος γέννησης.")).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: "Η επιλογή του/της (Όλα)" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByText("Με «Μόνο πρόοδος» ή «Τίποτα», η κάρτα του/της γράφει «Το όρισε ο coach σου».")).toBeInTheDocument();
  });
});

describe("«What they see on the card»", () => {
  it("starts on the client's own choice and names it", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view({ body_weight_kg: 80, birth_year: null, display: "progress_only" }));
    renderPanel();

    expect(await screen.findByRole("radio", { name: "Their choice (Progress only)" })).toHaveAttribute("aria-checked", "true");
  });

  it("starts on the coach's override when there is one", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view(null, "none"));
    renderPanel();

    expect(await screen.findByRole("radio", { name: "Nothing" })).toHaveAttribute("aria-checked", "true");
  });

  it.each([
    ["Progress only", "progress_only"],
    ["Nothing", "none"],
  ] as const)("saves «%s» as the override", async (label, display) => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(filled);
    vi.mocked(saveClientFitnessDisplay).mockResolvedValue({ ...filled, override: display });
    renderPanel();

    fireEvent.click(await screen.findByRole("radio", { name: label }));
    save();

    await waitFor(() => expect(saveClientFitnessDisplay).toHaveBeenCalledWith("access", client, display));
    await waitFor(() => expect(choice(label)).toHaveAttribute("aria-checked", "true"));
    expect(await screen.findByText("Changes saved.")).toBeInTheDocument();
  });

  it("saves the client's own choice as no override (null)", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view(filled.settings, "progress_only"));
    vi.mocked(saveClientFitnessDisplay).mockResolvedValue(filled);
    renderPanel();

    fireEvent.click(await screen.findByRole("radio", { name: "Their choice (All)" }));
    save();

    await waitFor(() => expect(saveClientFitnessDisplay).toHaveBeenCalledWith("access", client, null));
  });

  it("shows a 403 on save inside the form and keeps the choice", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(filled);
    vi.mocked(saveClientFitnessDisplay).mockRejectedValue(notYourClient());
    renderPanel();

    fireEvent.click(await screen.findByRole("radio", { name: "Nothing" }));
    save();

    const bar = screen.getByTestId("client-fitness-display-save-bar");
    expect(await within(bar).findByText(en.Ui.rhErrNotYourClient)).toBeInTheDocument();
    expect(choice("Nothing")).toHaveAttribute("aria-checked", "true");
  });

  it("says when the client's own choice is stricter and stays", async () => {
    vi.mocked(fetchClientFitnessDisplay).mockResolvedValue(view({ body_weight_kg: null, birth_year: null, display: "none" }));
    renderPanel();

    fireEvent.click(await screen.findByRole("radio", { name: "Progress only" }));
    expect(screen.getByTestId("client-fitness-stricter")).toHaveTextContent("Maria chose “Nothing”, which is stricter, so that stays.");
  });
});

describe("client-fitness-display helpers", () => {
  it("map the choice to the override and back", () => {
    expect(coachChoice(undefined)).toBe("client");
    expect(coachChoice(view(null, "none"))).toBe("none");
    expect(overrideFor("client")).toBeNull();
    expect(overrideFor("progress_only")).toBe("progress_only");
  });

  it("know the strictest choice wins", () => {
    const own = view({ body_weight_kg: null, birth_year: null, display: "progress_only" });
    expect(clientChoiceWins(own, "none")).toBe(false);
    expect(clientChoiceWins(own, "progress_only")).toBe(false);
    expect(clientChoiceWins(view({ body_weight_kg: null, birth_year: null, display: "none" }), "progress_only")).toBe(true);
    expect(clientChoiceWins(view(null), "progress_only")).toBe(false);
  });

  it("have no facts without a weight or a birth year", () => {
    expect(personalFacts(view(null))).toBeNull();
    expect(personalFacts(view({ body_weight_kg: null, birth_year: null, display: "all" }))).toBeNull();
    expect(personalFacts(filled)).toEqual({ weightKg: 72.5, birthYear: 1988 });
  });
});
