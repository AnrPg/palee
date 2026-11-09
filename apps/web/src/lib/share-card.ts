/**
 * ADR-565: the share card of a finished WOD, a new PR or a finished
 * challenge, drawn on a canvas and shared as an image (Instagram Stories,
 * TikTok, Facebook, WhatsApp… through the device's share sheet). Layout
 * decisions live in pure functions so they are testable without a canvas;
 * `paintShareCard` only paints them. Colours and font come from the theme
 * (SHARE_CARD_TOKENS, the dark variant, like the link previews).
 */

import { SHARE_CARD_TOKENS as card, THEME_FONTS } from "@/lib/theme";

export type ShareCardFormat = "story" | "square";

export const SHARE_CARD_SIZE: Record<ShareCardFormat, { width: number; height: number }> = {
  story: { width: 1080, height: 1920 },
  square: { width: 1080, height: 1080 },
};

/** What the card says. Every line is optional except the title. */
export type ShareCardData = {
  /** «WOD · Milos method», «PR», «Challenge». */
  eyebrow: string;
  title: string;
  /** The big number: 3:42, 120 kg, 21/21. */
  score?: string | null;
  /** Exercises and loads, or what the challenge was. */
  detail?: string | null;
  /** «Νέο PR · −0:18». */
  badge?: string | null;
  /** «#3 από 18 στο Milos method». */
  place?: string | null;
  /** «Hey pal, the real PR is coming back πάλι (palee)!» */
  tagline?: string | null;
  /** Localised date. */
  date: string;
  /** palee.app */
  site: string;
};

/** A workout exercise as far as the card cares. */
export type CardExercise = {
  item_type?: "exercise" | "header";
  name: string;
  load_value?: number | null;
  load_mode?: string | null;
};

/**
 * «Thrusters 43 kg · Pull-ups · Box jumps +2»: the first exercises with an
 * absolute load where the coach set one, then how many more there are.
 * Headers and empty names are skipped, repeated names shown once.
 */
export function exercisesLine(exercises: CardExercise[], unit = "kg", max = 3): string | null {
  const seen = new Set<string>();
  const parts: string[] = [];
  for (const exercise of exercises) {
    if (exercise.item_type === "header") continue;
    const name = exercise.name?.trim();
    if (!name || seen.has(name.toLocaleLowerCase())) continue;
    seen.add(name.toLocaleLowerCase());
    const load =
      exercise.load_mode === "absolute" && typeof exercise.load_value === "number" && exercise.load_value > 0
        ? ` ${Number(exercise.load_value.toFixed(1))} ${unit}`
        : "";
    parts.push(`${name}${load}`);
  }
  if (parts.length === 0) return null;
  const shown = parts.slice(0, max).join(" · ");
  return parts.length > max ? `${shown} +${parts.length - max}` : shown;
}

/** The viewer's place on a day leaderboard, when they are on it and opted in. */
export function leaderboardPlace(
  rows: Array<{ rank: number; me: boolean; opted_in: boolean }>,
): { rank: number; total: number } | null {
  const mine = rows.find((row) => row.me);
  if (!mine || !mine.opted_in) return null;
  return { rank: mine.rank, total: rows.filter((row) => row.opted_in).length };
}

/** Splits text into lines no wider than `maxWidth`, at most `maxLines` (the last ends with …). */
export function wrapText(text: string, maxWidth: number, measure: (value: string) => number, maxLines = 3): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (measure(next) <= maxWidth || !current) {
      current = next;
      continue;
    }
    lines.push(current);
    current = word;
  }
  if (current) lines.push(current);
  if (lines.length <= maxLines) return lines;
  const kept = lines.slice(0, maxLines);
  let last = kept[maxLines - 1];
  while (last.length > 1 && measure(`${last}…`) > maxWidth) last = last.slice(0, -1).trimEnd();
  kept[maxLines - 1] = `${last}…`;
  return kept;
}

/** The share card's colours: the dark theme, so the card reads as Palee in any feed. */
function palette() {
  return {
    background: card.primary,
    backgroundEnd: card.deep,
    text: card.deepContrast,
    accent: card.spark,
    accentText: card.sparkContrast,
    soft: card.textSoft,
  };
}

function drawCover(ctx: CanvasRenderingContext2D, image: CanvasImageSource & { width: number; height: number }, width: number, height: number) {
  const scale = Math.max(width / image.width, height / image.height);
  const w = image.width * scale;
  const h = image.height * scale;
  ctx.drawImage(image, (width - w) / 2, (height - h) / 2, w, h);
}

/** Paints the card; returns the canvas so callers can export it. */
export function paintShareCard(
  canvas: HTMLCanvasElement,
  data: ShareCardData,
  format: ShareCardFormat,
  photo?: (CanvasImageSource & { width: number; height: number }) | null,
): HTMLCanvasElement {
  const { width, height } = SHARE_CARD_SIZE[format];
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) return canvas;
  const colors = palette();
  const family = THEME_FONTS.sans;
  const pad = 88;
  const inner = width - pad * 2;
  const story = format === "story";

  // Background: the photo with a dark fade, or the brand gradient.
  if (photo) {
    drawCover(ctx, photo, width, height);
    const fade = ctx.createLinearGradient(0, height * 0.25, 0, height);
    fade.addColorStop(0, "transparent");
    fade.addColorStop(1, colors.backgroundEnd);
    ctx.globalAlpha = 0.85;
    ctx.fillStyle = fade;
    ctx.fillRect(0, 0, width, height);
    ctx.globalAlpha = 1;
  } else {
    const gradient = ctx.createLinearGradient(0, 0, width * 0.6, height);
    gradient.addColorStop(0, colors.background);
    gradient.addColorStop(1, colors.backgroundEnd);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
  }

  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "start";
  const font = (weight: number, size: number) => `${weight} ${size}px ${family}`;
  const measureWith = (f: string) => (value: string) => {
    ctx.font = f;
    return ctx.measureText(value).width;
  };

  // With a photo the text sits at the bottom so the photo shows; without, at the top.
  const blocks: Array<{ font: string; color: string; lines: string[]; size: number; gapAfter: number; pill?: boolean }> = [];
  const eyebrowFont = font(700, 34);
  blocks.push({ font: eyebrowFont, color: colors.soft, lines: [data.eyebrow.toLocaleUpperCase()], size: 34, gapAfter: 26 });
  const titleSize = story ? 92 : 80;
  blocks.push({
    font: font(800, titleSize),
    color: colors.text,
    lines: wrapText(data.title, inner, measureWith(font(800, titleSize)), 2),
    size: titleSize,
    gapAfter: 24,
  });
  if (data.score) {
    const scoreSize = story ? 200 : 160;
    blocks.push({ font: font(900, scoreSize), color: colors.accent, lines: [data.score], size: scoreSize, gapAfter: 28 });
  }
  if (data.detail) {
    blocks.push({
      font: font(500, 40),
      color: colors.soft,
      lines: wrapText(data.detail, inner, measureWith(font(500, 40)), story ? 3 : 2),
      size: 40,
      gapAfter: 26,
    });
  }
  if (data.badge) blocks.push({ font: font(800, 40), color: colors.accentText, lines: [data.badge], size: 40, gapAfter: 26, pill: true });
  if (data.place) blocks.push({ font: font(700, 44), color: colors.text, lines: [data.place], size: 44, gapAfter: 20 });

  const lineGap = 1.18;
  const blockHeight = blocks.reduce(
    (sum, block) => sum + block.lines.length * block.size * lineGap + block.gapAfter + (block.pill ? 24 : 0),
    0,
  );
  const footerTop = height - pad - (data.tagline ? 110 : 40);
  // A Story without a photo sits a little above the middle, like a poster.
  let y = photo
    ? Math.max(pad + 40, footerTop - blockHeight - 30)
    : story
      ? Math.max(pad + 40, (footerTop - blockHeight) / 2 - 40)
      : pad + 40;

  for (const block of blocks) {
    ctx.font = block.font;
    for (const line of block.lines) {
      if (block.pill) {
        const w = ctx.measureText(line).width + 56;
        const h = block.size + 30;
        ctx.fillStyle = colors.accent;
        ctx.beginPath();
        ctx.roundRect(pad, y, w, h, h / 2);
        ctx.fill();
        ctx.fillStyle = block.color;
        ctx.fillText(line, pad + 28, y + block.size + 6);
        y += h;
      } else {
        y += block.size;
        ctx.fillStyle = block.color;
        ctx.fillText(line, pad, y);
        y += block.size * (lineGap - 1);
      }
    }
    y += block.gapAfter;
  }

  // Footer: tagline, then the site and the date.
  if (data.tagline) {
    ctx.font = font(600, 34);
    ctx.fillStyle = colors.soft;
    const lines = wrapText(data.tagline, inner, measureWith(font(600, 34)), 2);
    lines.forEach((line, index) => ctx.fillText(line, pad, height - pad - 70 - (lines.length - 1 - index) * 42));
  }
  ctx.font = font(700, 34);
  ctx.fillStyle = colors.text;
  ctx.fillText(data.site, pad, height - pad);
  ctx.textAlign = "end";
  ctx.fillStyle = colors.soft;
  ctx.fillText(data.date, width - pad, height - pad);
  ctx.textAlign = "start";
  return canvas;
}

/** The card as a JPEG file, ready for the share sheet or an upload. */
export async function renderShareCard(
  data: ShareCardData,
  format: ShareCardFormat,
  photo?: (CanvasImageSource & { width: number; height: number }) | null,
  name = "palee.jpg",
): Promise<File> {
  const canvas = paintShareCard(document.createElement("canvas"), data, format, photo);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
  if (!blob) throw new Error("share card could not be drawn");
  return new File([blob], name, { type: "image/jpeg" });
}

/** A picked photo as something the canvas can draw. */
export async function loadPhoto(file: Blob): Promise<ImageBitmap | HTMLImageElement> {
  if (typeof createImageBitmap === "function") {
    try {
      return await createImageBitmap(file, { imageOrientation: "from-image" });
    } catch {
      // Fall through to an <img>, which every browser decodes.
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    return image;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export type ShareOutcome = "shared" | "cancelled" | "downloaded";

/**
 * Hands the card to the device's share sheet (Instagram, TikTok, Facebook,
 * WhatsApp…). Must run inside the tap's handler: nothing may be awaited
 * before it. Where files cannot be shared (desktop, Android's in-app
 * WebView), the card is saved instead.
 */
export async function shareCardFile(file: File, text: string): Promise<ShareOutcome> {
  const nav = typeof navigator !== "undefined" ? navigator : null;
  if (nav && typeof nav.share === "function" && typeof nav.canShare === "function" && nav.canShare({ files: [file] })) {
    try {
      await nav.share({ files: [file], text });
      return "shared";
    } catch (caught) {
      if (caught instanceof DOMException && caught.name === "AbortError") return "cancelled";
      // Some browsers refuse after all (e.g. a lost tap); saving still works.
    }
  }
  const url = URL.createObjectURL(file);
  const link = document.createElement("a");
  link.href = url;
  link.download = file.name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return "downloaded";
}
