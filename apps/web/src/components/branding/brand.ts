/**
 * The words that are Palee's own and read the same in every locale, so they
 * live here and not in the message catalogs: the name, the host and the
 * tagline (ANR 2026-11-08: never translated, «πάλι» always in Greek).
 */
export { BRAND_NAME } from "@/lib/seo/site-info";

export const PALEE_HOST = "palee.app";

/** The tagline in its three parts: the English lead, the Greek word, the gloss. */
export const PALEE_TAGLINE_PARTS = {
  lead: "Hey pal, the real PR is coming back",
  word: "πάλι",
  gloss: "(palee)",
} as const;

export const PALEE_TAGLINE = `${PALEE_TAGLINE_PARTS.lead} ${PALEE_TAGLINE_PARTS.word} ${PALEE_TAGLINE_PARTS.gloss}!`;
