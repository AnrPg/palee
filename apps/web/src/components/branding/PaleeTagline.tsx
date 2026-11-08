/**
 * The Palee tagline (ANR 2026-11-08). It is the same words in every locale:
 * never translated, «πάλι» always in Greek and «(palee)» after it.
 */
import { PALEE_TAGLINE_PARTS } from "@/components/branding/brand";

export { PALEE_TAGLINE } from "@/components/branding/brand";

export function PaleeTagline({
  className = "",
  accent = "var(--primary)",
}: {
  className?: string;
  /** The colour of «πάλι»: Spark on the dark landing, the brand blue elsewhere. */
  accent?: string;
}) {
  return (
    <p lang="en" dir="ltr" className={`font-semibold tracking-tight ${className}`} data-testid="palee-tagline">
      {PALEE_TAGLINE_PARTS.lead}{" "}
      <span lang="el" className="font-extrabold" style={{ color: accent }}>
        {PALEE_TAGLINE_PARTS.word}
      </span>{" "}
      <span className="opacity-70">{PALEE_TAGLINE_PARTS.gloss}</span>!
    </p>
  );
}
