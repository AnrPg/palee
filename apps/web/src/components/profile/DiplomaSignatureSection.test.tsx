import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { DEFAULT_SIGNATURE_LIMITS, normalizeSignatureState } from "@/api/diploma-signature";
import { DiplomaSignatureSection } from "@/components/profile/DiplomaSignatureSection";

const getDiplomaSignature = vi.fn();
const getDiplomaSignatureImage = vi.fn();
const uploadDiplomaSignature = vi.fn();
const deleteDiplomaSignature = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" }, currentUser: { id: "u-1", display_name: "Nikos P." } }),
}));

vi.mock("@/api/diploma-signature", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/diploma-signature")>();
  return {
    ...actual,
    getDiplomaSignature: (...args: unknown[]) => getDiplomaSignature(...args),
    getDiplomaSignatureImage: (...args: unknown[]) => getDiplomaSignatureImage(...args),
    uploadDiplomaSignature: (...args: unknown[]) => uploadDiplomaSignature(...args),
    deleteDiplomaSignature: (...args: unknown[]) => deleteDiplomaSignature(...args),
  };
});

const stored = { id: "s-1", content_type: "image/png", byte_size: 2048, width: 600, height: 200, updated_at: "2026-11-03T10:00:00Z" };

function state(signature: typeof stored | null, eligible = true) {
  return { eligible, signature, limits: DEFAULT_SIGNATURE_LIMITS };
}

async function openSection() {
  fireEvent.click(await screen.findByRole("button", { name: /title/ }));
}

function pick(file: File) {
  fireEvent.change(screen.getByLabelText("fieldLabel"), { target: { files: [file] } });
}

describe("DiplomaSignatureSection (ADR-377 addendum)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getDiplomaSignatureImage.mockResolvedValue(new Blob(["png"], { type: "image/png" }));
    URL.createObjectURL = vi.fn(() => "blob:signature");
    URL.revokeObjectURL = vi.fn();
  });

  it("is hidden for people who do not award ranks, and for a malformed answer", async () => {
    getDiplomaSignature.mockResolvedValue(normalizeSignatureState({}));
    const { container } = render(<DiplomaSignatureSection />);
    await waitFor(() => expect(getDiplomaSignature).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
  });

  it("uploads a PNG and shows the preview above the name line", async () => {
    getDiplomaSignature.mockResolvedValue(state(null));
    uploadDiplomaSignature.mockResolvedValue(stored);
    render(<DiplomaSignatureSection />);
    await openSection();
    expect(screen.getByText("empty")).toBeInTheDocument();

    pick(new File([new Uint8Array([137, 80, 78, 71])], "sig.png", { type: "image/png" }));

    await waitFor(() => expect(uploadDiplomaSignature).toHaveBeenCalledWith("token", expect.stringMatching(/^data:image\/png;base64,/)));
    expect(await screen.findByAltText("previewAlt")).toHaveAttribute("src", "blob:signature");
    expect(screen.getByText('signedAs:{"name":"Nikos P."}')).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "replace" })).toBeInTheDocument();
  });

  it("refuses other file types before sending, with the error under the field", async () => {
    getDiplomaSignature.mockResolvedValue(state(null));
    render(<DiplomaSignatureSection />);
    await openSection();

    pick(new File(["gif"], "sig.gif", { type: "image/gif" }));

    expect(await screen.findByText("errorType")).toBeInTheDocument();
    expect(screen.getByLabelText("fieldLabel")).toHaveAttribute("aria-invalid", "true");
    expect(uploadDiplomaSignature).not.toHaveBeenCalled();
  });

  it("refuses a file over the size limit before sending", async () => {
    getDiplomaSignature.mockResolvedValue({ ...state(null), limits: { ...DEFAULT_SIGNATURE_LIMITS, max_bytes: 4 } });
    render(<DiplomaSignatureSection />);
    await openSection();

    pick(new File([new Uint8Array(10)], "sig.png", { type: "image/png" }));

    expect(await screen.findByText(/^errorSize/)).toBeInTheDocument();
    expect(uploadDiplomaSignature).not.toHaveBeenCalled();
  });

  it("shows the server's reason when it refuses the image", async () => {
    getDiplomaSignature.mockResolvedValue(state(null));
    uploadDiplomaSignature.mockRejectedValue(new ApiError(422, "small", { code: "signature_too_small", error: "small" }));
    render(<DiplomaSignatureSection />);
    await openSection();

    pick(new File([new Uint8Array([1])], "sig.jpg", { type: "image/jpeg" }));

    expect(await screen.findByText('errorSmall:{"width":60,"height":20}')).toBeInTheDocument();
  });

  it("removes the signature", async () => {
    getDiplomaSignature.mockResolvedValue(state(stored));
    deleteDiplomaSignature.mockResolvedValue(undefined);
    render(<DiplomaSignatureSection />);
    await openSection();

    fireEvent.click(await screen.findByRole("button", { name: "remove" }));

    await waitFor(() => expect(deleteDiplomaSignature).toHaveBeenCalledWith("token"));
    expect(await screen.findByText("empty")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "remove" })).not.toBeInTheDocument();
  });
});

describe("normalizeSignatureState", () => {
  it("reads a malformed answer as not eligible with default limits", () => {
    expect(normalizeSignatureState(null)).toEqual({ eligible: false, signature: null, limits: DEFAULT_SIGNATURE_LIMITS });
    expect(normalizeSignatureState({ eligible: true, signature: { nope: 1 }, limits: { max_bytes: 10 } })).toEqual({
      eligible: true,
      signature: null,
      limits: { ...DEFAULT_SIGNATURE_LIMITS, max_bytes: 10 },
    });
  });
});
