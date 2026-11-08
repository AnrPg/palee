/**
 * The Palee tagline (ANR 2026-11-08). It is the same words in every locale:
 * never translated, «πάλι» always in Greek and «(palee)» after it.
 */
export const PALEE_TAGLINE = "Hey pal, the real PR is coming back πάλι (palee)!";

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
      Hey pal, the real PR is coming back{" "}
      <span lang="el" className="font-extrabold" style={{ color: accent }}>
        πάλι
      </span>{" "}
      <span className="opacity-70">(palee)</span>!
    </p>
  );
}
