import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import en from "../../../../../messages/en.json";

import { InlineAssignPackage } from "./InlineAssignPackage";

// ADR-660: the ledger's package menu. For a member who already holds a
// package, picking another one changes it (after a confirm) instead of
// quietly adding a second package that keeps billing beside it.

const packages = [
  { id: "p1", name: "Monthly", active: true },
  { id: "p2", name: "Free", active: true },
];

function menu(props: Partial<Parameters<typeof InlineAssignPackage>[0]> = {}) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <InlineAssignPackage
        userId="u1"
        currentCode={null}
        currentLabel={null}
        packages={packages}
        pending={false}
        onAssign={vi.fn().mockResolvedValue({})}
        {...props}
      />
    </NextIntlClientProvider>,
  );
}

async function pick(label: string) {
  fireEvent.click(screen.getByRole("combobox"));
  const option = await screen.findByRole("option", { name: label });
  fireEvent.click(option);
}

describe("InlineAssignPackage", () => {
  it("assigns straight away when the member holds no package", async () => {
    const onAssign = vi.fn().mockResolvedValue({});
    const onChange = vi.fn();
    const { container } = menu({ onAssign, onChange });

    fireEvent.click(container.querySelector("button")!);
    await pick("Free");
    expect(screen.queryByTestId("package-change-open")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Assign" }));

    await waitFor(() => expect(onAssign).toHaveBeenCalledWith("p2"));
    expect(onChange).not.toHaveBeenCalled();
  });

  it("changes the held package, and adds a second one only when asked", async () => {
    const onAssign = vi.fn().mockResolvedValue({});
    const onChange = vi.fn();
    menu({ currentLabel: "Monthly", onAssign, onChange, onRemove: vi.fn() });

    fireEvent.click(screen.getByRole("button", { name: /Monthly/ }));
    await pick("Free");
    fireEvent.click(screen.getByTestId("package-change-open"));

    expect(onChange).toHaveBeenCalledWith({ id: "p2", name: "Free" });
    expect(onAssign).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: /Monthly/ }));
    await pick("Free");
    fireEvent.click(screen.getByTestId("package-add-alongside"));
    await waitFor(() => expect(onAssign).toHaveBeenCalledWith("p2"));
  });
});
