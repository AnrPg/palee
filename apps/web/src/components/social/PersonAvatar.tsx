import { clubInitials } from "@/components/community/community";

/**
 * A person's photo, or their initials on a neutral disc. `size` is pixels, or
 * "fill" to take the parent's box (the profile header scales it, and the initials, with its width).
 */
export function PersonAvatar({ name, url, size = 40 }: { name?: string | null; url?: string | null; size?: number | "fill" }) {
  const box = size === "fill" ? "100%" : size;
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
    return <img src={url} alt="" className="shrink-0 rounded-full object-cover" style={{ width: box, height: box }} />;
  }
  return (
    <span
      aria-hidden="true"
      className={`flex shrink-0 items-center justify-center rounded-full font-extrabold ${size === "fill" ? "text-[clamp(1.25rem,8cqi,1.9rem)]" : ""}`}
      style={{ width: box, height: box, fontSize: size === "fill" ? undefined : size * 0.36, background: "var(--panel-raised)", color: "var(--text)" }}
    >
      {clubInitials(name ?? "?")}
    </span>
  );
}
