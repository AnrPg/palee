/**
 * ADR-530: the 12 website palettes and the `--s-*` tokens a template paints
 * with. Palettes apply to the box's website only; the Palee app keeps its one
 * theme. Accent text that fails WCAG AA on the page background is darkened
 * (light) or lightened (dark) until it passes.
 */

export const PALETTE_KEYS = [
  "palee",
  "electric",
  "flame",
  "sun",
  "amber",
  "emerald",
  "aegean",
  "violet",
  "fuchsia",
  "olive",
  "navy",
  "mono",
] as const;
export type PaletteKey = (typeof PALETTE_KEYS)[number];

export const TEMPLATE_KEYS = ["arena", "tiles", "stories", "atelier"] as const;
export type TemplateKey = (typeof TEMPLATE_KEYS)[number];

export const APPEARANCES = ["auto", "light", "dark"] as const;
export type Appearance = (typeof APPEARANCES)[number];

/** accent, second accent, deep (dark surfaces and the dark background's base). */
export const PALETTES: Record<PaletteKey, { accent: string; accent2: string; deep: string }> = {
  palee: { accent: "#2F5BFF", accent2: "#C8FF4D", deep: "#141A33" },
  electric: { accent: "#B6F23A", accent2: "#2F5BFF", deep: "#121410" },
  flame: { accent: "#E0203F", accent2: "#FF9F1C", deep: "#1E0F12" },
  sun: { accent: "#FF6B1A", accent2: "#FFC233", deep: "#22140B" },
  amber: { accent: "#E9A800", accent2: "#1F3A5F", deep: "#1B1609" },
  emerald: { accent: "#0F9D6B", accent2: "#B8E04A", deep: "#0C1A15" },
  aegean: { accent: "#0B8FA3", accent2: "#FF7A59", deep: "#0B1A1F" },
  violet: { accent: "#7C3AED", accent2: "#F472B6", deep: "#170F26" },
  fuchsia: { accent: "#E0368C", accent2: "#5B2BE0", deep: "#200D18" },
  olive: { accent: "#6E7F2E", accent2: "#D9A441", deep: "#15170D" },
  navy: { accent: "#1D4E89", accent2: "#E3B23C", deep: "#0C1524" },
  mono: { accent: "#17181C", accent2: "#8A8F99", deep: "#0F1012" },
};

export function isPaletteKey(value: unknown): value is PaletteKey {
  return typeof value === "string" && (PALETTE_KEYS as readonly string[]).includes(value);
}
export function isTemplateKey(value: unknown): value is TemplateKey {
  return typeof value === "string" && (TEMPLATE_KEYS as readonly string[]).includes(value);
}

type RGB = [number, number, number];
const toRgb = (hex: string): RGB => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)) as RGB;
const toHex = (rgb: RGB) =>
  "#" + rgb.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, "0")).join("").toUpperCase();

/** Mixes `a` towards `b` by `t` (0..1). */
export function mix(a: string, b: string, t: number) {
  const x = toRgb(a);
  const y = toRgb(b);
  return toHex([0, 1, 2].map((i) => x[i]! * (1 - t) + y[i]! * t) as RGB);
}

function luminance(hex: string) {
  const c = toRgb(hex).map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * c[0]! + 0.7152 * c[1]! + 0.0722 * c[2]!;
}

export function contrast(a: string, b: string) {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

/** White or near-black text, whichever reads better on `hex`. */
export function onColor(hex: string) {
  return contrast(hex, "#FFFFFF") >= contrast(hex, "#111111") ? "#FFFFFF" : "#111111";
}

function readable(color: string, background: string, toward: string) {
  let x = color;
  for (let i = 0; i < 20 && contrast(x, background) < 4.5; i++) x = mix(x, toward, 0.12);
  return x;
}

export type SiteTokens = Record<`--s-${string}`, string>;

/**
 * The template's tokens. `atelier` paints on warm paper instead of white.
 * `aa` is the contrast of accent text on the background (the settings page
 * shows it).
 */
export function siteTokens(palette: PaletteKey, dark: boolean, template: TemplateKey): { tokens: SiteTokens; aa: number } {
  const p = PALETTES[palette] ?? PALETTES.palee;
  const warm = template === "atelier";
  let accent = p.accent;
  let accent2 = p.accent2;
  let bg: string, surface: string, ink: string, muted: string, line: string, lineStrong: string;
  if (!dark) {
    bg = warm ? mix("#F7F4EF", accent, 0.03) : palette === "mono" ? "#F6F6F4" : mix("#FFFFFF", accent, 0.045);
    surface = warm ? "#FCFBF8" : "#FFFFFF";
    ink = mix(p.deep, "#000000", 0.25);
    muted = mix(ink, bg, 0.4);
    line = mix(ink, bg, 0.88);
    lineStrong = mix(ink, bg, 0.7);
  } else {
    bg = mix(p.deep, "#000000", 0.25);
    surface = mix(bg, "#FFFFFF", 0.07);
    ink = mix("#FFFFFF", accent, 0.06);
    muted = mix(ink, bg, 0.38);
    line = mix(ink, bg, 0.86);
    lineStrong = mix(ink, bg, 0.68);
    if (palette === "mono") {
      accent = "#F2F2F0";
      accent2 = "#8A8F99";
    } else if (contrast(accent, bg) < 3) {
      accent = mix(accent, "#FFFFFF", 0.25);
    }
  }
  const accentInk = readable(accent, bg, dark ? "#FFFFFF" : "#000000");
  const tokens: SiteTokens = {
    "--s-bg": bg,
    "--s-surface": surface,
    "--s-ink": ink,
    "--s-muted": muted,
    "--s-line": line,
    "--s-line-strong": lineStrong,
    "--s-accent": accent,
    "--s-on-accent": onColor(accent),
    "--s-accent2": accent2,
    "--s-on-accent2": onColor(accent2),
    "--s-accent-ink": accentInk,
    "--s-deep": p.deep,
    "--s-on-deep": "#F2F1EE",
    "--s-ok": dark ? "#3DDC84" : "#138A4B",
    "--s-err": dark ? "#FF8A8A" : "#B42318",
    "--s-star": dark ? "#FFC94D" : "#B7791F",
    // Pure white and black, only for text and scrims over photos (ADR-530).
    "--s-white": "#FFFFFF",
    "--s-black": "#000000",
  };
  return { tokens, aa: contrast(accentInk, bg) };
}
