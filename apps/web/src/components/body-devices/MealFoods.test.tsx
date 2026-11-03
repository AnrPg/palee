import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { MealFoods } from "./MealFoods";

const lookUpBarcode = vi.fn();
const createCustomFood = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/body-devices", () => ({
  lookUpBarcode: (...args: unknown[]) => lookUpBarcode(...args),
  createCustomFood: (...args: unknown[]) => createCustomFood(...args),
}));

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>
);

function open(onChange = vi.fn()) {
  render(<MealFoods foods={[]} onChange={onChange} />, { wrapper });
  fireEvent.click(screen.getByText("foods.scan"));
  return onChange;
}

function type(code: string) {
  fireEvent.change(screen.getByLabelText(/foods.typeIt/), { target: { value: code } });
  fireEvent.click(screen.getByText("foods.find"));
}

describe("MealFoods (ADR-376, mockups d9scan A and d9manual A)", () => {
  beforeEach(() => {
    lookUpBarcode.mockReset();
    createCustomFood.mockReset();
  });

  it("marks a wrong code inside the form and does not ask", () => {
    open();
    type("5201054017105");
    expect(screen.getByText("foods.invalidBarcode")).toBeInTheDocument();
    expect(lookUpBarcode).not.toHaveBeenCalled();
  });

  it("adds a found product with its suggested hand portion, never calories, grams hidden without a coach's macros", async () => {
    lookUpBarcode.mockResolvedValue({
      barcode: "5201054017104",
      status: "found",
      source: "open_food_facts",
      macros_visible: false,
      attribution: { source: "Open Food Facts", licence: "ODbL 1.0", licence_url: "u", images_licence: "CC BY-SA", url: "https://world.openfoodfacts.org/product/5201054017104" },
      food: { name: "Strained yogurt 2%", brand: "Sandbox Dairy", barcode: "5201054017104", portion_hint: "protein", nutrients: { proteins: 10, carbohydrates: 3.8, fat: 2 } },
    });
    const onChange = open();
    type("5201054017104");
    expect(await screen.findByTestId("barcode-found")).toHaveTextContent("Strained yogurt 2%");
    expect(screen.queryByText(/foods.per100g/)).not.toBeInTheDocument();
    expect(screen.getByText(/foods.source/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "foods.portion.protein" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByText("foods.add"));
    expect(onChange).toHaveBeenCalledWith([{ name: "Strained yogurt 2%", barcode: "5201054017104", portion: "protein" }]);
  });

  it("shows grams per 100 g only when the server allows them", async () => {
    lookUpBarcode.mockResolvedValue({
      barcode: "5201054017104",
      status: "found",
      macros_visible: true,
      attribution: null,
      food: { name: "Yogurt", portion_hint: null, nutrients: { proteins: 10, carbohydrates: 3.8, fat: 2 } },
    });
    open();
    type("5201054017104");
    expect(await screen.findByText(/foods.per100g/)).toBeInTheDocument();
  });

  it("turns into «Δικό μου τρόφιμο» when nothing is found, the name required", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "5201054017104", status: "manual", reason: "not_found", macros_visible: false });
    createCustomFood.mockResolvedValue({ id: "f1", name: "Grandma's rusk", portion_hint: "carbs", nutrients: null });
    const onChange = open();
    type("5201054017104");
    expect(await screen.findByText("foods.notFoundTitle")).toBeInTheDocument();
    fireEvent.click(screen.getByText("foods.saveOwn"));
    expect(screen.getByText("foods.nameRequired")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/foods.name/), { target: { value: "Grandma's rusk" } });
    fireEvent.click(screen.getByRole("button", { name: "foods.portion.carbs" }));
    fireEvent.click(screen.getByText("foods.saveOwn"));
    await waitFor(() =>
      expect(createCustomFood).toHaveBeenCalledWith("tok", { name: "Grandma's rusk", barcode: "5201054017104", portion_hint: "carbs" }),
    );
    await waitFor(() => expect(onChange).toHaveBeenCalledWith([{ name: "Grandma's rusk", custom_food_id: "f1", portion: "carbs" }]));
  });

  it("says a shop-printed code is not a product and keeps no barcode", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "2012345678903", status: "manual", reason: "in_store_code", macros_visible: false });
    open();
    type("2012345678903");
    expect(await screen.findByText("foods.storeCodeTitle")).toBeInTheDocument();
  });
});
