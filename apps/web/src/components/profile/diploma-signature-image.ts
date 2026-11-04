import type { DiplomaSignatureLimits } from "@/api/diploma-signature";

/** What the person may pick; a WebP is turned into a PNG here (a PDF cannot hold WebP). */
export const SIGNATURE_ACCEPT = "image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp";

const PICKABLE = ["image/png", "image/jpeg", "image/webp"];

export type PreparedSignature =
  | { ok: true; blob: Blob }
  | { ok: false; error: "type" | "size" };

type Decoded = { width: number; height: number; source: CanvasImageSource; close?: () => void };

async function decode(file: Blob): Promise<Decoded | null> {
  if (typeof createImageBitmap !== "function") return null;
  try {
    const bitmap = await createImageBitmap(file);
    return { width: bitmap.width, height: bitmap.height, source: bitmap, close: () => bitmap.close() };
  } catch {
    return null;
  }
}

async function redraw(decoded: Decoded, limits: DiplomaSignatureLimits): Promise<Blob | null> {
  const scale = Math.min(1, limits.max_width / decoded.width, limits.max_height / decoded.height);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(decoded.width * scale));
  canvas.height = Math.max(1, Math.round(decoded.height * scale));
  const context = canvas.getContext("2d");
  if (!context) return null;
  context.drawImage(decoded.source, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve) => canvas.toBlob((blob) => resolve(blob), "image/png"));
}

/**
 * Checks a picked file and makes it uploadable: PNG and JPEG go as they
 * are; a WebP, or an image larger than the limits, is redrawn as a PNG
 * (transparency kept) that fits them. The server checks again.
 */
export async function prepareSignatureFile(file: File, limits: DiplomaSignatureLimits): Promise<PreparedSignature> {
  if (!PICKABLE.includes(file.type)) return { ok: false, error: "type" };

  let blob: Blob = file;
  const decoded = await decode(file);
  try {
    const tooLarge = decoded ? decoded.width > limits.max_width || decoded.height > limits.max_height : false;
    if (file.type === "image/webp" || tooLarge) {
      if (!decoded) return { ok: false, error: "type" };
      const png = await redraw(decoded, limits);
      if (!png) return { ok: false, error: "type" };
      blob = png;
    }
  } finally {
    decoded?.close?.();
  }

  if (blob.size > limits.max_bytes) return { ok: false, error: "size" };
  return { ok: true, blob };
}

export function readAsDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.onerror = () => reject(reader.error ?? new Error("read failed"));
    reader.readAsDataURL(blob);
  });
}
