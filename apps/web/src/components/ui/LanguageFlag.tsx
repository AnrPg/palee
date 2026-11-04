import { flagSrc } from "@/lib/language-flags";

/** A language's flag (ADR-545): a small SVG, decorative next to its code and name. */
export function LanguageFlag({ code, size = 20, className = "" }: { code: string; size?: number; className?: string }) {
  const src = flagSrc(code);
  if (!src) return <span aria-hidden="true" className={`inline-block shrink-0 ${className}`} style={{ width: size, height: Math.round((size * 3) / 4) }} />;
  return (
    // eslint-disable-next-line @next/next/no-img-element -- a 1 KB static SVG; next/image adds nothing here
    <img
      src={src}
      alt=""
      aria-hidden="true"
      width={size}
      height={Math.round((size * 3) / 4)}
      className={`inline-block shrink-0 rounded-[3px] object-cover ${className}`}
      style={{ boxShadow: "0 0 0 1px var(--border)" }}
      data-flag={code}
    />
  );
}
