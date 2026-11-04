import type { components } from "@/api/generated/schema";

/**
 * The cover photo editor's maths (ADR-541), pure. The cover is a 16:9 window
 * on the photo: the photo turns by right angles, the window shrinks as it
 * zooms and moves with drags, and brightness scales every pixel.
 *
 * Units: `centerX`/`centerY` are where the window's centre sits, in fractions
 * of the photo after rotation (0–1). The crop the API stores is in the same
 * fractions (x, y, width, height of the window).
 */

export type CoverEditInput = components["schemas"]["ProgrammeCoverEdit"];
export type Rotation = 0 | 90 | 180 | 270;
export type ImageSize = { width: number; height: number };

export type CoverEdit = {
  rotation: Rotation;
  zoom: number;
  brightness: number;
  centerX: number;
  centerY: number;
};

export const COVER_ASPECT = 16 / 9;
/** The smallest cover the API takes, in the photo's own pixels (ADR-541 §3). */
export const COVER_MIN_WIDTH = 320;
export const COVER_MAX_ZOOM = 4;
export const COVER_MIN_BRIGHTNESS = 0.5;
export const COVER_MAX_BRIGHTNESS = 1.5;
/** The rendered cover is at most this wide. */
export const COVER_OUTPUT_WIDTH = 1920;

export const INITIAL_COVER_EDIT: CoverEdit = { rotation: 0, zoom: 1, brightness: 1, centerX: 0.5, centerY: 0.5 };

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const finite = (value: unknown, fallback: number) => (typeof value === "number" && Number.isFinite(value) ? value : fallback);

export function normalizeRotation(degrees: number): Rotation {
  const value = ((Math.round(degrees / 90) * 90) % 360 + 360) % 360;
  return value as Rotation;
}

/** The photo's size once turned. */
export function rotatedSize(image: ImageSize, rotation: Rotation): ImageSize {
  return rotation === 90 || rotation === 270 ? { width: image.height, height: image.width } : image;
}

/** The largest 16:9 window on the turned photo, in its pixels (zoom 1). */
export function baseWindow(image: ImageSize, rotation: Rotation): ImageSize {
  const turned = rotatedSize(image, rotation);
  if (turned.width / turned.height > COVER_ASPECT) return { width: turned.height * COVER_ASPECT, height: turned.height };
  return { width: turned.width, height: turned.width / COVER_ASPECT };
}

/** A photo too small for a 320 × 180 cover at any zoom. */
export function isTooSmall(image: ImageSize) {
  return baseWindow(image, 0).width < COVER_MIN_WIDTH - 0.5;
}

/** How far the photo may zoom while the cover keeps at least 320 of its pixels across. */
export function maxZoom(image: ImageSize, rotation: Rotation) {
  return clamp(baseWindow(image, rotation).width / COVER_MIN_WIDTH, 1, COVER_MAX_ZOOM);
}

/** The window in pixels of the turned photo. */
export function windowSize(image: ImageSize, edit: Pick<CoverEdit, "rotation" | "zoom">): ImageSize {
  const base = baseWindow(image, edit.rotation);
  return { width: base.width / edit.zoom, height: base.height / edit.zoom };
}

/** Zoom, brightness and rotation in range, and the window fully on the photo. */
export function clampEdit(image: ImageSize, edit: CoverEdit): CoverEdit {
  const rotation = normalizeRotation(finite(edit.rotation, 0));
  const zoom = clamp(finite(edit.zoom, 1), 1, maxZoom(image, rotation));
  const brightness = clamp(finite(edit.brightness, 1), COVER_MIN_BRIGHTNESS, COVER_MAX_BRIGHTNESS);
  const turned = rotatedSize(image, rotation);
  const window = windowSize(image, { rotation, zoom });
  const halfX = window.width / turned.width / 2;
  const halfY = window.height / turned.height / 2;
  return {
    rotation,
    zoom,
    brightness,
    centerX: clamp(finite(edit.centerX, 0.5), halfX, 1 - halfX),
    centerY: clamp(finite(edit.centerY, 0.5), halfY, 1 - halfY),
  };
}

/** The crop in fractions of the turned photo, as the API stores it. */
export function cropOf(image: ImageSize, edit: CoverEdit) {
  const clamped = clampEdit(image, edit);
  const turned = rotatedSize(image, clamped.rotation);
  const window = windowSize(image, clamped);
  const width = window.width / turned.width;
  const height = window.height / turned.height;
  return { x: clamped.centerX - width / 2, y: clamped.centerY - height / 2, width, height };
}

/**
 * Moves the photo under the window by a drag, given in window widths and
 * heights (dragging right shows more of the left of the photo).
 */
export function panBy(image: ImageSize, edit: CoverEdit, dx: number, dy: number): CoverEdit {
  const turned = rotatedSize(image, edit.rotation);
  const window = windowSize(image, edit);
  return clampEdit(image, {
    ...edit,
    centerX: edit.centerX - (dx * window.width) / turned.width,
    centerY: edit.centerY - (dy * window.height) / turned.height,
  });
}

export function zoomTo(image: ImageSize, edit: CoverEdit, zoom: number): CoverEdit {
  return clampEdit(image, { ...edit, zoom });
}

export function brightnessTo(image: ImageSize, edit: CoverEdit, brightness: number): CoverEdit {
  return clampEdit(image, { ...edit, brightness });
}

/** Turns the photo by 90° clockwise, keeping the same spot under the window's centre. */
export function rotateClockwise(image: ImageSize, edit: CoverEdit): CoverEdit {
  return clampEdit(image, {
    ...edit,
    rotation: normalizeRotation(edit.rotation + 90),
    centerX: 1 - edit.centerY,
    centerY: edit.centerX,
  });
}

const round = (value: number) => Math.round(value * 1e6) / 1e6;

/** The edit as `PUT /programmes/:id/cover` takes it. */
export function toApiEdit(image: ImageSize, edit: CoverEdit): Required<CoverEditInput> {
  const clamped = clampEdit(image, edit);
  const crop = cropOf(image, clamped);
  return {
    rotation: clamped.rotation,
    zoom: round(clamped.zoom),
    brightness: round(clamped.brightness),
    crop: { x: round(crop.x), y: round(crop.y), width: round(crop.width), height: round(crop.height) },
  };
}

/** A stored edit back into the editor (editing again starts from the original). */
export function fromApiEdit(image: ImageSize, stored: CoverEditInput | null | undefined): CoverEdit {
  if (!stored) return clampEdit(image, INITIAL_COVER_EDIT);
  const rotation = normalizeRotation(finite(stored.rotation, 0));
  const crop = stored.crop;
  const base = baseWindow(image, rotation);
  const turned = rotatedSize(image, rotation);
  const zoom = stored.zoom ?? (crop && crop.width > 0 ? base.width / (crop.width * turned.width) : 1);
  return clampEdit(image, {
    rotation,
    zoom,
    brightness: finite(stored.brightness, 1),
    centerX: crop ? crop.x + crop.width / 2 : 0.5,
    centerY: crop ? crop.y + crop.height / 2 : 0.5,
  });
}

/** The rendered cover's size: the window's own pixels, at most 1920 across. */
export function outputSize(image: ImageSize, edit: CoverEdit): ImageSize {
  const window = windowSize(image, clampEdit(image, edit));
  const width = Math.max(COVER_MIN_WIDTH, Math.min(COVER_OUTPUT_WIDTH, Math.round(window.width)));
  return { width, height: Math.round(width / COVER_ASPECT) };
}

/**
 * How to draw the photo on an output canvas of `output` pixels: translate
 * to (translateX, translateY), rotate by `radians`, then draw the photo
 * centred at the origin at `width` × `height`.
 */
export function drawPlan(image: ImageSize, edit: CoverEdit, output: ImageSize) {
  const clamped = clampEdit(image, edit);
  const turned = rotatedSize(image, clamped.rotation);
  const window = windowSize(image, clamped);
  const scale = output.width / window.width;
  // The turned photo's centre, relative to the window's centre, in output pixels.
  const offsetX = (0.5 - clamped.centerX) * turned.width * scale;
  const offsetY = (0.5 - clamped.centerY) * turned.height * scale;
  return {
    translateX: output.width / 2 + offsetX,
    translateY: output.height / 2 + offsetY,
    radians: (clamped.rotation * Math.PI) / 180,
    width: image.width * scale,
    height: image.height * scale,
  };
}

/** Brightness on RGBA pixels, in place (alpha untouched). */
export function applyBrightness(pixels: Uint8ClampedArray, brightness: number) {
  if (brightness === 1) return pixels;
  for (let index = 0; index < pixels.length; index += 4) {
    pixels[index] = pixels[index] * brightness;
    pixels[index + 1] = pixels[index + 1] * brightness;
    pixels[index + 2] = pixels[index + 2] * brightness;
  }
  return pixels;
}
