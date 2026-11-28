import { clubInitials } from "@/components/community/community";
import { AvatarButton } from "@/components/social/AvatarViewer";

/**
 * A person's photo, or their initials on a neutral disc. `size` is pixels, or
 * "fill" to take the parent's box (the profile header scales it, and the initials, with its width).
 *
 * With `personId` a photo opens full size on a press (ANR 2026-11-28); the
 * row or card around it keeps going to the profile. Initials stay as they
 * are, so pressing them still reaches whatever wraps them (the profile).
 */
export function PersonAvatar({
  name,
  url,
  size = 40,
  personId,
  onProfile = false,
}: {
  name?: string | null;
  url?: string | null;
  size?: number | "fill";
  /** The person behind the photo: makes it open the photo viewer. */
  personId?: string | null;
  /** Already on this person's profile (the viewer then offers only «Πολυμέσα»). */
  onProfile?: boolean;
}) {
  const box = size === "fill" ? "100%" : size;
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
    const photo = <img src={url} alt="" className="shrink-0 rounded-full object-cover" style={{ width: box, height: box }} />;
    if (!personId) return photo;
    return (
      <AvatarButton personId={personId} name={name ?? "?"} url={url} onProfile={onProfile} style={{ width: box, height: box }}>
        {photo}
      </AvatarButton>
    );
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
