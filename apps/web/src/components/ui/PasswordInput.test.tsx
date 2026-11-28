import { readFileSync } from "node:fs";
import { join } from "node:path";

import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../messages/el.json";
import en from "../../../messages/en.json";

import { AuthField } from "@/components/auth/AuthField";
import { SUPPORTED_LOCALES } from "@/i18n/locales";

import { MaskableInput, PasswordInput } from "./PasswordInput";

function withIntl(
  node: React.ReactNode,
  messages: Record<string, unknown> = en,
  locale = "en",
) {
  return render(
    <NextIntlClientProvider locale={locale} messages={messages}>
      {node}
    </NextIntlClientProvider>,
  );
}

describe("ui/PasswordInput", () => {
  it("masks the value and shows it while the eye is on", () => {
    withIntl(
      <PasswordInput
        id="pw"
        aria-label="Password"
        defaultValue="secret1"
        className="w-full"
        style={{ color: "var(--text)" }}
      />,
    );
    const input = screen.getByLabelText("Password");
    expect(input).toHaveAttribute("type", "password");
    // Room for the eye at the end of the field, colours from the theme.
    expect(input).toHaveStyle({
      paddingInlineEnd: "2.75rem",
      color: "var(--text)",
    });

    const show = screen.getByRole("button", { name: "Show password" });
    expect(show).toHaveAttribute("type", "button");
    expect(show).toHaveAttribute("aria-controls", "pw");
    fireEvent.click(show);
    expect(input).toHaveAttribute("type", "text");
    expect(input).toHaveValue("secret1");

    fireEvent.click(screen.getByRole("button", { name: "Hide password" }));
    expect(input).toHaveAttribute("type", "password");
  });

  it("speaks of a key for API secrets, in the person's language", () => {
    withIntl(<PasswordInput aria-label="Κλειδί" kind="key" />, el, "el");
    expect(
      screen.getByRole("button", { name: "Εμφάνιση κλειδιού" }),
    ).toBeInTheDocument();
  });

  it("disables the eye with a disabled field", () => {
    withIntl(<PasswordInput aria-label="Password" disabled />);
    expect(
      screen.getByRole("button", { name: "Show password" }),
    ).toBeDisabled();
  });

  it("MaskableInput leaves a non-secret field plain, with its own type", () => {
    withIntl(
      <>
        <MaskableInput masked={false} type="email" aria-label="Email" />
        <MaskableInput masked aria-label="Token" kind="key" />
      </>,
    );
    expect(screen.getByLabelText("Email")).toHaveAttribute("type", "email");
    expect(screen.getByLabelText("Token")).toHaveAttribute("type", "password");
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });

  it("AuthField password fields get the same eye", () => {
    withIntl(
      <AuthField
        label="Password"
        type="password"
        value="abc12345"
        onChange={() => undefined}
      />,
    );
    const input = screen.getByLabelText("Password");
    expect(input).toHaveAttribute("type", "password");
    fireEvent.click(screen.getByRole("button", { name: "Show password" }));
    expect(input).toHaveAttribute("type", "text");
  });

  // Plain JSON reads, not module imports: transforming 12 large message
  // files through the bundler took over 5 s on CI (2026-11-23).
  it("every locale names the button", () => {
    const messagesDir = join(__dirname, "..", "..", "..", "messages");
    for (const locale of SUPPORTED_LOCALES) {
      const messages = JSON.parse(
        readFileSync(join(messagesDir, `${locale}.json`), "utf8"),
      ) as {
        Common: Record<string, string>;
      };
      for (const key of [
        "showPassword",
        "hidePassword",
        "showKey",
        "hideKey",
      ]) {
        expect(messages.Common[key], `${locale}.${key}`).toBeTruthy();
      }
    }
  }, 30_000);
});
