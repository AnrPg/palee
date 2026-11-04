import { completeProgrammeCover, requestProgrammeCoverUpload, setProgrammeCover } from "@/api/programme-covers";
import { loadAvatarImage, type AvatarImage } from "@/components/profile/avatar-crop";
import { fitWithin } from "@/lib/post-media";
import { putPresigned } from "@/lib/presigned-upload";

import { applyBrightness, drawPlan, outputSize, toApiEdit, type CoverEdit, type ImageSize } from "./cover-edit-model";

/**
 * The browser side of a cover photo (ADR-541, ADR-148): the photo is
 * re-encoded here (which drops EXIF and GPS), edited on a canvas, and both
 * the original and the rendered 16:9 cover are uploaded.
 */
export type CoverImage = AvatarImage;

/** The original is kept at most 2400 px on its long edge, like box photos. */
const ORIGINAL_MAX_EDGE = 2400;
const QUALITY = 0.86;

export class CoverUploadError extends Error {
  constructor(public readonly reason: "unsupported" | "storage") {
    super(reason);
    this.name = "CoverUploadError";
  }
}

/** Loads a picked file, or the stored original by URL, upright. */
export function loadCoverImage(source: File | string, signal?: AbortSignal) {
  return loadAvatarImage(source, signal);
}

/** The size the editor works in: the original as it will be uploaded. */
export function workingSize(image: ImageSize): ImageSize {
  return fitWithin(image.width, image.height, ORIGINAL_MAX_EDGE);
}

function canvasBlob(canvas: HTMLCanvasElement, type: string) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, QUALITY));
}

/** WebP, or JPEG where the browser cannot encode WebP. */
async function encode(canvas: HTMLCanvasElement): Promise<Blob> {
  const webp = await canvasBlob(canvas, "image/webp");
  if (webp?.type === "image/webp") return webp;
  const jpeg = await canvasBlob(canvas, "image/jpeg");
  if (!jpeg) throw new CoverUploadError("unsupported");
  return jpeg;
}

/** Draws the edited cover onto `canvas` at the canvas's size. */
export function drawCover(canvas: HTMLCanvasElement, image: CoverImage, size: ImageSize, edit: CoverEdit) {
  const context = canvas.getContext("2d", { willReadFrequently: edit.brightness !== 1 });
  if (!context) return;
  const plan = drawPlan(size, edit, { width: canvas.width, height: canvas.height });
  context.setTransform(1, 0, 0, 1, 0, 0);
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.imageSmoothingQuality = "high";
  context.translate(plan.translateX, plan.translateY);
  context.rotate(plan.radians);
  context.drawImage(image, -plan.width / 2, -plan.height / 2, plan.width, plan.height);
  context.setTransform(1, 0, 0, 1, 0, 0);
  if (edit.brightness !== 1) {
    // Pixel maths rather than `context.filter`, which some browsers lack.
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
    applyBrightness(pixels.data, edit.brightness);
    context.putImageData(pixels, 0, 0);
  }
}

async function renderOriginal(image: CoverImage, size: ImageSize) {
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  canvas.getContext("2d")?.drawImage(image, 0, 0, size.width, size.height);
  try {
    return await encode(canvas);
  } finally {
    canvas.width = 0;
    canvas.height = 0;
  }
}

async function renderCover(image: CoverImage, size: ImageSize, edit: CoverEdit) {
  const output = outputSize(size, edit);
  const canvas = document.createElement("canvas");
  canvas.width = output.width;
  canvas.height = output.height;
  drawCover(canvas, image, size, edit);
  try {
    return await encode(canvas);
  } finally {
    canvas.width = 0;
    canvas.height = 0;
  }
}

/** Reserve, PUT to storage, then let the API verify it. */
async function upload(token: string, blob: Blob) {
  const contentType = blob.type === "image/webp" ? "image/webp" : "image/jpeg";
  const reserved = await requestProgrammeCoverUpload(token, { content_type: contentType, byte_size: blob.size });
  try {
    await putPresigned(reserved.upload_url, blob, reserved.required_headers);
  } catch {
    throw new CoverUploadError("storage");
  }
  const media = await completeProgrammeCover(token, reserved.media_id);
  return media.id ?? reserved.media_id;
}

/**
 * Saves the cover: a newly picked photo uploads its original too; editing
 * again keeps the stored original (`originalMediaId`) and uploads only the
 * new render.
 */
export async function saveCover(
  token: string,
  programmeId: string,
  input: { image: CoverImage; size: ImageSize; edit: CoverEdit; originalMediaId?: string | null },
) {
  const originalMediaId = input.originalMediaId ?? (await upload(token, await renderOriginal(input.image, input.size)));
  const mediaId = await upload(token, await renderCover(input.image, input.size, input.edit));
  return setProgrammeCover(token, programmeId, {
    media_id: mediaId,
    original_media_id: originalMediaId,
    edit: toApiEdit(input.size, input.edit),
  });
}
