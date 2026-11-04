import { describe, expect, it } from "vitest";

import {
  applyBrightness,
  baseWindow,
  brightnessTo,
  clampEdit,
  cropOf,
  drawPlan,
  fromApiEdit,
  INITIAL_COVER_EDIT,
  isTooSmall,
  maxZoom,
  outputSize,
  panBy,
  rotateClockwise,
  toApiEdit,
  zoomTo,
} from "./cover-edit-model";

const landscape = { width: 2400, height: 1600 };
const portrait = { width: 1200, height: 1800 };
const ratio = (image: { width: number; height: number }, crop: { width: number; height: number }, rotation: 0 | 90 | 180 | 270 = 0) => {
  const turned = rotation % 180 ? { width: image.height, height: image.width } : image;
  return (crop.width * turned.width) / (crop.height * turned.height);
};

describe("cover window (ADR-541)", () => {
  it("is the largest 16:9 window at zoom 1", () => {
    expect(baseWindow(landscape, 0)).toEqual({ width: 2400, height: 1350 });
    expect(baseWindow(portrait, 0)).toEqual({ width: 1200, height: 675 });
    expect(baseWindow(portrait, 90)).toEqual({ width: 1800 * 1, height: 1012.5 });
  });

  it("keeps the crop at 16:9 in the photo's pixels, rotated or not", () => {
    const crop = cropOf(portrait, { ...INITIAL_COVER_EDIT, zoom: 2 });
    expect(ratio(portrait, crop)).toBeCloseTo(16 / 9, 6);
    const turned = rotateClockwise(portrait, INITIAL_COVER_EDIT);
    expect(turned.rotation).toBe(90);
    expect(ratio(portrait, cropOf(portrait, turned), 90)).toBeCloseTo(16 / 9, 6);
  });

  it("never zooms past 4× or below 320 photo pixels across", () => {
    expect(maxZoom(landscape, 0)).toBe(4);
    expect(maxZoom({ width: 960, height: 540 }, 0)).toBe(3);
    expect(zoomTo(landscape, INITIAL_COVER_EDIT, 9).zoom).toBe(4);
    expect(zoomTo(landscape, INITIAL_COVER_EDIT, 0.2).zoom).toBe(1);
  });

  it("says when a photo is too small for a cover", () => {
    expect(isTooSmall({ width: 300, height: 300 })).toBe(true);
    expect(isTooSmall({ width: 640, height: 480 })).toBe(false);
  });

  it("keeps the window on the photo when dragged past an edge", () => {
    const zoomed = zoomTo(landscape, INITIAL_COVER_EDIT, 2);
    const dragged = panBy(landscape, zoomed, 10, 0);
    const crop = cropOf(landscape, dragged);
    expect(crop.x).toBeCloseTo(0, 6);
    const other = cropOf(landscape, panBy(landscape, zoomed, -10, -10));
    expect(other.x + other.width).toBeCloseTo(1, 6);
    expect(other.y + other.height).toBeCloseTo(1, 6);
  });

  it("clamps brightness between 0.5 and 1.5", () => {
    expect(brightnessTo(landscape, INITIAL_COVER_EDIT, 3).brightness).toBe(1.5);
    expect(clampEdit(landscape, { ...INITIAL_COVER_EDIT, brightness: 0 }).brightness).toBe(0.5);
  });

  it("goes to the API and back without drifting", () => {
    const edit = panBy(landscape, zoomTo(landscape, rotateClockwise(landscape, INITIAL_COVER_EDIT), 1.5), 0.2, 0.1);
    const stored = toApiEdit(landscape, { ...edit, brightness: 1.2 });
    expect(stored.rotation).toBe(90);
    expect(stored.brightness).toBe(1.2);
    const back = fromApiEdit(landscape, stored);
    expect(back.zoom).toBeCloseTo(edit.zoom, 4);
    expect(back.centerX).toBeCloseTo(edit.centerX, 4);
    expect(back.centerY).toBeCloseTo(edit.centerY, 4);
    expect(fromApiEdit(landscape, null)).toEqual(INITIAL_COVER_EDIT);
  });

  it("renders at the window's own pixels, at most 1920 across, 16:9", () => {
    expect(outputSize(landscape, INITIAL_COVER_EDIT)).toEqual({ width: 1920, height: 1080 });
    expect(outputSize(landscape, { ...INITIAL_COVER_EDIT, zoom: 4 })).toEqual({ width: 600, height: 338 });
  });

  it("draws the photo centred when nothing moved, and shifted when the window moved", () => {
    const plan = drawPlan(landscape, INITIAL_COVER_EDIT, { width: 1600, height: 900 });
    expect(plan.translateX).toBeCloseTo(800);
    expect(plan.translateY).toBeCloseTo(450);
    expect(plan.width).toBeCloseTo(1600);
    const moved = drawPlan(landscape, panBy(landscape, zoomTo(landscape, INITIAL_COVER_EDIT, 2), -10, 0), { width: 1600, height: 900 });
    expect(moved.translateX).toBeLessThan(800);
  });

  it("scales the colour of every pixel and leaves alpha alone", () => {
    expect([...applyBrightness(new Uint8ClampedArray([100, 200, 250, 128]), 1.2)]).toEqual([120, 240, 255, 128]);
  });
});
