import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { MealFoods } from "./MealFoods";

const lookUpBarcode = vi.fn();
const createCustomFood = vi.fn();
const readFoodLabel = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/body-devices", () => ({
  lookUpBarcode: (...args: unknown[]) => lookUpBarcode(...args),
  createCustomFood: (...args: unknown[]) => createCustomFood(...args),
  readFoodLabel: (...args: unknown[]) => readFoodLabel(...args),
}));
vi.mock("@/lib/box-photo-upload", () => ({ reencodeImage: async (file: Blob) => file }));

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
    readFoodLabel.mockReset();
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

  it("offers «Φωτογραφία ετικέτας» only when the server can read labels", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "5201054017104", status: "manual", reason: "not_found", macros_visible: false });
    open();
    type("5201054017104");
    expect(await screen.findByText("foods.notFoundTitle")).toBeInTheDocument();
    expect(screen.queryByText("foods.labelPhoto")).not.toBeInTheDocument();
  });

  it("prefills the own food from the label photos; the member saves it with the grams per 100 g", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "5201054017104", status: "manual", reason: "not_found", macros_visible: true, label_reading: true });
    readFoodLabel.mockResolvedValue({
      macros_visible: true,
      food: { name: "Φέτα ΠΟΠ", brand: "Sandbox Dairy", serving_label: "30 g", portion_hint: "fat", nutrients: { proteins: 17, fat: 21.5 } },
    });
    createCustomFood.mockResolvedValue({ id: "f2", name: "Φέτα ΠΟΠ", portion_hint: "fat", nutrients: null });
    const onChange = open();
    type("5201054017104");
    fireEvent.click(await screen.findByText("foods.labelPhoto"));
    fireEvent.click(screen.getByText("foods.labelRead"));
    expect(screen.getByText("foods.labelNeedPhoto")).toBeInTheDocument();
    expect(readFoodLabel).not.toHaveBeenCalled();
    const photo = new File(["jpeg"], "front.jpg", { type: "image/jpeg" });
    fireEvent.change(screen.getByLabelText(/foods.labelFront/), { target: { files: [photo] } });
    fireEvent.click(screen.getByText("foods.labelRead"));
    await waitFor(() => expect(screen.getByLabelText(/foods.name/)).toHaveValue("Φέτα ΠΟΠ"));
    expect(readFoodLabel).toHaveBeenCalledWith("tok", { front: photo, nutrition: null });
    expect(screen.getByLabelText(/foods.brand/)).toHaveValue("Sandbox Dairy");
    expect(screen.getByLabelText(/foods.nutrient.proteins/)).toHaveValue("17");
    expect(screen.getByRole("button", { name: "foods.portion.fat" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.change(screen.getByLabelText(/foods.nutrient.salt/), { target: { value: "300" } });
    fireEvent.click(screen.getByText("foods.saveOwn"));
    expect(screen.getByText("foods.nutrientInvalid")).toBeInTheDocument();
    expect(createCustomFood).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText(/foods.nutrient.salt/), { target: { value: "2,4" } });
    fireEvent.click(screen.getByText("foods.saveOwn"));
    await waitFor(() =>
      expect(createCustomFood).toHaveBeenCalledWith("tok", {
        name: "Φέτα ΠΟΠ",
        barcode: "5201054017104",
        brand: "Sandbox Dairy",
        serving_label: "30 g",
        portion_hint: "fat",
        nutrients: { proteins: 17, fat: 21.5, salt: 2.4 },
      }),
    );
    await waitFor(() => expect(onChange).toHaveBeenCalledWith([{ name: "Φέτα ΠΟΠ", custom_food_id: "f2", portion: "fat" }]));
  });

  it("keeps the grams out of the form without a coach's macros, and says when a label can't be read", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "5201054017104", status: "manual", reason: "not_found", macros_visible: false, label_reading: true });
    readFoodLabel.mockRejectedValue(new Error("422"));
    open();
    type("5201054017104");
    fireEvent.click(await screen.findByText("advanced"));
    expect(screen.queryByTestId("own-food-nutrients")).not.toBeInTheDocument();
    fireEvent.click(screen.getByText("foods.labelPhoto"));
    fireEvent.change(screen.getByLabelText(/foods.labelTable/), { target: { files: [new File(["x"], "t.jpg", { type: "image/jpeg" })] } });
    fireEvent.click(screen.getByText("foods.labelRead"));
    expect(await screen.findByText("foods.labelUnreadable")).toBeInTheDocument();
  });

  it("says a shop-printed code is not a product and keeps no barcode", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "2012345678903", status: "manual", reason: "in_store_code", macros_visible: false });
    open();
    type("2012345678903");
    expect(await screen.findByText("foods.storeCodeTitle")).toBeInTheDocument();
    expect(screen.queryByTestId("own-food-share")).not.toBeInTheDocument();
  });

  it("shares a barcoded own food only when the member ticks «Μοιράσου το» (ADR-421 addendum)", async () => {
    lookUpBarcode.mockResolvedValue({ barcode: "5201054017104", status: "manual", reason: "not_found", macros_visible: false });
    createCustomFood.mockResolvedValue({ id: "f3", name: "Rusk", portion_hint: null, nutrients: null, shared_at: "2026-11-03T10:00:00Z" });
    open();
    type("5201054017104");
    const share = await screen.findByTestId("own-food-share");
    expect(share).not.toBeChecked();
    expect(screen.getByText("foods.staysYours")).toBeInTheDocument();
    expect(screen.getByText("foods.shareHelp")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/foods.name/), { target: { value: "Rusk" } });
    fireEvent.click(share);
    expect(screen.queryByText("foods.staysYours")).not.toBeInTheDocument();
    fireEvent.click(screen.getByText("foods.saveOwn"));
    await waitFor(() => expect(createCustomFood).toHaveBeenCalledWith("tok", { name: "Rusk", barcode: "5201054017104", share: true }));
  });

  it("marks a product members shared with «από μέλη»", async () => {
    lookUpBarcode.mockResolvedValue({
      barcode: "5201054017104",
      status: "found",
      source: "palee_members",
      macros_visible: false,
      attribution: { source: "Palee members", licence: "ODbL-1.0", licence_url: "u", images_licence: null, url: null },
      food: { name: "Rusk", barcode: "5201054017104", portion_hint: "carbs", nutrients: null },
    });
    open();
    type("5201054017104");
    expect(await screen.findByTestId("from-members")).toHaveTextContent("foods.fromMembers");
    expect(screen.getByText("foods.source:foods.membersSource,ODbL-1.0")).toBeInTheDocument();
  });
});
