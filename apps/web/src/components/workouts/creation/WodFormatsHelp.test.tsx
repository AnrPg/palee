import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { fireEvent, render, screen, within } from "@testing-library/react";
import { createTranslator, NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../../messages/el.json";
import { readFormatLine } from "@/lib/wod-formats/parse";

import { explainTimer, HELP_EXAMPLES, WodFormatsHelpButton } from "./WodFormatsHelp";

const LOCALES = ["el", "en", "ar", "bg", "de", "es", "fr", "he", "it", "nl", "pt-PT", "ru"];

describe("the WOD formats help (ADR-650)", () => {
  it.each(LOCALES)("%s: every example sets a timer and says what it does", (locale) => {
    const messages = JSON.parse(readFileSync(resolve(__dirname, `../../../../messages/${locale}.json`), "utf8"));
    const t = createTranslator({ locale, messages, namespace: "WodFormatsHelp" });
    for (const key of HELP_EXAMPLES) {
      const line = t(`examples.${key}`);
      const preset = readFormatLine(line)?.preset ?? null;
      expect([locale, line, preset === null]).toEqual([locale, line, false]);
      expect(explainTimer(t as never, preset!)).toMatch(/\S/);
    }
  });

  it("explains a timer in plain words", () => {
    const t = createTranslator({ locale: "el", messages: el, namespace: "WodFormatsHelp" });
    expect(explainTimer(t as never, { format: "amrap", duration_seconds: 720 })).toBe("Μετράει 12 λεπτά. Κάνεις όσους γύρους προλάβεις.");
    expect(explainTimer(t as never, { format: "emom", interval_seconds: 120, rounds: 5 })).toBe(
      "Κάθε 2 λεπτά ξεκινάς από την αρχή, 5 φορές. Σύνολο 10 λεπτά.",
    );
    expect(explainTimer(t as never, { format: "custom_hiit", work_seconds: 90, rest_seconds: 30, rounds: 1 })).toBe(
      "1 λεπτό και 30 δευτερόλεπτα δουλειά, 30 δευτερόλεπτα ξεκούραση, 1 φορά.",
    );
  });

  it("opens from its button, tries a line, and fills the box from an example", () => {
    render(
      <NextIntlClientProvider locale="el" messages={el}>
        <WodFormatsHelpButton freeText />
      </NextIntlClientProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: /Πώς γράφω το χρονόμετρο;/ }));
    const dialog = screen.getByTestId("wod-formats-help");
    expect(within(dialog).getAllByTestId("wod-formats-help-example")).toHaveLength(HELP_EXAMPLES.length);
    expect(within(dialog).getByText(/Το ελεύθερο κείμενο έχει ένα χρονόμετρο/)).toBeInTheDocument();

    const input = within(dialog).getByTestId("wod-formats-help-try");
    const result = within(dialog).getByTestId("wod-formats-help-result");
    fireEvent.change(input, { target: { value: "AMRAP 12" } });
    expect(within(result).getByTestId("wod-formats-help-chip")).toHaveTextContent("AMRAP");
    expect(result).toHaveTextContent("Μετράει 12 λεπτά.");
    fireEvent.change(input, { target: { value: "AMRAP" } });
    expect(result).toHaveTextContent("Γράψε και τα λεπτά");
    fireEvent.change(input, { target: { value: "Superset" } });
    expect(result).toHaveTextContent("δεν βάζει χρονόμετρο");
    fireEvent.change(input, { target: { value: "Back squat 5x5" } });
    expect(result).toHaveTextContent("Δεν βρέθηκε χρονόμετρο ακόμα");

    fireEvent.click(within(dialog).getAllByRole("button", { name: "Δοκίμασέ το" })[2]!);
    expect(input).toHaveValue("Κάθε 2 λεπτά x 5");
    expect(result).toHaveTextContent("Κάθε 2 λεπτά ξεκινάς από την αρχή, 5 φορές.");
  });
});
