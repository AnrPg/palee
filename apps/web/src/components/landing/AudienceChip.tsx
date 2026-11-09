import Link from "next/link";

/**
 * The chip beside the Palee logo on the two signed-out landings: it always
 * points to the other one (athletes ⇄ business, ADR-556). One place for it,
 * so both pages say it the same way and it never drifts to the sign-in side.
 */
export function AudienceChip({ href, label, testId, className = "" }: { href: string; label: string; testId: string; className?: string }) {
  return (
    <Link
      href={href}
      className={`inline-flex min-h-9 shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-3 text-[11px] font-extrabold uppercase tracking-[0.12em] transition-colors hover:bg-[color-mix(in_srgb,var(--deep-contrast)_12%,transparent)] ${className}`}
      style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 35%, transparent)", color: "var(--deep-contrast)" }}
      data-testid={testId}
    >
      {label}
      <span aria-hidden="true">→</span>
    </Link>
  );
}
