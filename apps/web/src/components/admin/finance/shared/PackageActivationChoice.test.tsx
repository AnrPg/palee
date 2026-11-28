import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";

import { PackageActivationChoice } from "./PackageActivationChoice";

function wrap(children: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      {children}
    </NextIntlClientProvider>,
  );
}

describe("PackageActivationChoice (ADR-795, 2A)", () => {
  it("asks what happened with the money and never invents a payment", () => {
    const onLater = vi.fn();
    const onPaidNow = vi.fn();
    wrap(<PackageActivationChoice packageName="Unlimited" priceCents={5000} pending={false} onLater={onLater} onPaidNow={onPaidNow} onFree={vi.fn()} onBack={vi.fn()} />);
    expect(screen.getByText(/^Τα .*50.*;$/)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("package-activate-later"));
    expect(onLater).toHaveBeenCalled();
    fireEvent.click(screen.getByTestId("package-activate-paid-now"));
    expect(onPaidNow).toHaveBeenCalled();
  });

  it("«Χωρίς χρέωση» is looked at once more, with an optional reason", () => {
    const onFree = vi.fn();
    wrap(<PackageActivationChoice packageName="Unlimited" priceCents={5000} pending={false} onLater={vi.fn()} onFree={onFree} onBack={vi.fn()} />);
    fireEvent.click(screen.getByTestId("package-activate-free"));
    expect(onFree).not.toHaveBeenCalled();
    fireEvent.change(screen.getByTestId("package-activate-free-reason"), { target: { value: "Νέος coach" } });
    fireEvent.click(screen.getByTestId("package-activate-free-submit"));
    expect(onFree).toHaveBeenCalledWith("Νέος coach");
  });
});
