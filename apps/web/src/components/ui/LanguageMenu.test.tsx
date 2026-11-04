import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { LanguageMenu } from "./LanguageMenu";

const wrap = (node: ReactNode) => render(<NextIntlClientProvider locale="en" messages={en}>{node}</NextIntlClientProvider>);

describe("ui/LanguageMenu (ADR-545)", () => {
  it("shows the current flag and code, and lists the current language first with flag, code and own name", () => {
    const choose = vi.fn();
    wrap(<LanguageMenu value="el" options={["en", "el", "ar"]} onChoose={choose} />);

    const button = screen.getByRole("button", { name: "Language: Ελληνικά" });
    expect(button).toHaveTextContent("EL");
    expect(button.querySelector('img[data-flag="el"]')).toHaveAttribute("src", "/flags/gr.svg");
    fireEvent.click(button);

    const list = screen.getByTestId("language-menu-list");
    const rows = within(list).getAllByRole("button").filter((row) => row.dataset.testid?.startsWith("language-menu-option-"));
    expect(rows.map((row) => row.dataset.testid)).toEqual(["language-menu-option-el", "language-menu-option-en", "language-menu-option-ar"]);
    expect(rows[0]).toHaveAttribute("aria-current", "true");
    expect(rows[2]).toHaveTextContent("AR");
    expect(within(rows[2]).getByText("العربية")).toHaveAttribute("dir", "rtl");
    expect(within(list).getByText("Other languages")).toBeInTheDocument();

    fireEvent.click(rows[1]);
    expect(choose).toHaveBeenCalledWith("en");
    expect(screen.queryByTestId("language-menu-list")).not.toBeInTheDocument();
  });

  it("makes each row a link to that language's address on a website", () => {
    wrap(<LanguageMenu value="el" options={["el", "en"]} hrefFor={(code) => (code === "el" ? "/b/kyp" : `/b/kyp/${code}`)} testId="site" />);
    fireEvent.click(screen.getByTestId("site"));
    expect(screen.getByTestId("site-option-en")).toHaveAttribute("href", "/b/kyp/en");
    expect(screen.getByTestId("site-option-en")).toHaveAttribute("hreflang", "en");
    expect(screen.getByTestId("site-option-el")).toHaveAttribute("aria-current", "page");
  });
});
