import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import type { StaffProgramme } from "@/api/programmes";

import { CoverEditor } from "./CoverEditor";

const upload = vi.hoisted(() => ({
  size: { width: 2400, height: 1600 },
  fail: false,
  save: vi.fn(),
  draw: vi.fn(),
}));

vi.mock("./cover-upload", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./cover-upload")>();
  return {
    ...actual,
    loadCoverImage: () => (upload.fail ? Promise.reject(new Error("decode")) : Promise.resolve({ ...upload.size })),
    drawCover: (...args: unknown[]) => upload.draw(...args),
    saveCover: (...args: unknown[]) => {
      upload.save(...args);
      return Promise.resolve({ id: "p-1" } as StaffProgramme);
    },
  };
});

function renderEditor(props: Partial<Parameters<typeof CoverEditor>[0]> = {}) {
  const onSaved = vi.fn();
  render(
    <QueryClientProvider client={new QueryClient()}>
      <NextIntlClientProvider locale="en" messages={en}>
        <CoverEditor
          programmeId="p-1"
          token="tok"
          source={new File(["x"], "photo.jpg", { type: "image/jpeg" })}
          storedEdit={null}
          originalMediaId={null}
          onClose={vi.fn()}
          onSaved={onSaved}
          {...props}
        />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return { onSaved };
}

describe("CoverEditor (ADR-541)", () => {
  beforeEach(() => {
    upload.size = { width: 2400, height: 1600 };
    upload.fail = false;
    upload.save.mockReset();
    upload.draw.mockReset();
  });

  it("turns, zooms and brightens the photo, then saves the edit with a new original", async () => {
    const { onSaved } = renderEditor();
    await waitFor(() => expect(screen.getByTestId("programme-cover-save")).toBeEnabled());
    fireEvent.click(screen.getByTestId("programme-cover-rotate"));
    fireEvent.change(screen.getByLabelText("Zoom"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Brightness"), { target: { value: "1.2" } });
    fireEvent.keyDown(screen.getByTestId("programme-cover-preview"), { key: "ArrowLeft" });
    fireEvent.click(screen.getByTestId("programme-cover-save"));
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    const [token, programmeId, input] = upload.save.mock.calls[0];
    expect([token, programmeId]).toEqual(["tok", "p-1"]);
    expect(input.originalMediaId).toBeNull();
    expect(input.edit).toMatchObject({ rotation: 90, zoom: 2, brightness: 1.2 });
    expect(upload.draw).toHaveBeenCalled();
  });

  it("starts again from the stored edit and keeps the stored original", async () => {
    renderEditor({ source: "https://media.example/original.webp", storedEdit: { rotation: 180, zoom: 1.5, brightness: 0.8, crop: { x: 0.1, y: 0.1, width: 0.6, height: 0.6 } }, originalMediaId: "m-0" });
    await waitFor(() => expect(screen.getByTestId("programme-cover-save")).toBeEnabled());
    expect(screen.getByLabelText("Brightness")).toHaveValue("0.8");
    fireEvent.click(screen.getByTestId("programme-cover-save"));
    await waitFor(() => expect(upload.save).toHaveBeenCalled());
    expect(upload.save.mock.calls[0][2]).toMatchObject({ originalMediaId: "m-0", edit: { rotation: 180, zoom: 1.5 } });
  });

  it("says when a photo is too small, inside the editor, and cannot save", async () => {
    upload.size = { width: 300, height: 200 };
    renderEditor();
    expect(await screen.findByText(/too small for a cover/)).toBeInTheDocument();
    expect(screen.getByTestId("programme-cover-save")).toBeDisabled();
  });

  it("says when a photo cannot be opened", async () => {
    upload.fail = true;
    renderEditor();
    expect(await screen.findByText("This photo could not be opened. Try another one.")).toBeInTheDocument();
  });
});
