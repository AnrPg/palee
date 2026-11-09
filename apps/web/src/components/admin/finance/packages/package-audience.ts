import type { AthleteOption } from "@/api/assigned-workouts";
import type { PeopleSearchPerson } from "@/api/conversations";
import type { BoxAudience, PackageAudience, PackageAudienceException, PackageAudienceSettings } from "@/api/package-audience";

/**
 * ADR-553: who sees the box's subscription packages. The rules are the
 * API's (`Finance.Domain.PackageAudience`); this file only shapes what the
 * settings show.
 */

export const BOX_AUDIENCES: BoxAudience[] = ["all", "own", "none"];
/** A package's choices; `null` follows the box («Όπως το box»), the default. */
export const PACKAGE_AUDIENCES: PackageAudience[] = [null, "all", "own", "none"];

/** A package's stored audience (`null` follows the box). */
export function packageAudience(pkg: { audience?: unknown } | null | undefined): PackageAudience {
  const value = pkg?.audience;
  return value === "all" || value === "own" || value === "none" ? value : null;
}

/** The settings as the page uses them, whatever the answer held: a known audience, a list of exceptions with a person. */
export function normalizeSettings(data: unknown): PackageAudienceSettings {
  const raw = (data && typeof data === "object" ? data : {}) as Partial<PackageAudienceSettings>;
  const audience = BOX_AUDIENCES.includes(raw.audience as BoxAudience) ? (raw.audience as BoxAudience) : "all";
  const exceptions = (Array.isArray(raw.exceptions) ? raw.exceptions : [])
    .filter((row) => row && typeof row.id === "string" && (row.effect === "show" || row.effect === "hide"))
    .map((row) => ({ ...row, person: row.person ?? { id: row.id, nickname: null, handle: null, avatar_url: null } }));
  const featured = typeof raw.featured_package_id === "string" ? raw.featured_package_id : null;
  return { audience, exceptions, featured_package_id: featured } as PackageAudienceSettings;
}

/** The person exceptions of one package, or of the whole box with `null`, «show» first. */
export function exceptionsFor(settings: PackageAudienceSettings | undefined, packageId: string | null): PackageAudienceException[] {
  const rows = (settings?.exceptions ?? []).filter((row) => (row.package_id ?? null) === packageId);
  return [...rows.filter((row) => row.effect === "show"), ...rows.filter((row) => row.effect === "hide")];
}

export type PersonOption = { id: string; label: string; handle: string | null; member: boolean };

/**
 * Who can be picked: the box's own people first (members and staff), then
 * anyone on Palee (ANR 2026-11-08: «both»), each once and never someone
 * already in the list.
 */
export function personOptions(members: AthleteOption[], people: PeopleSearchPerson[], taken: Iterable<string>, limit = 8): PersonOption[] {
  const skip = new Set(taken);
  const out: PersonOption[] = [];
  for (const member of Array.isArray(members) ? members : []) {
    if (skip.has(member.id)) continue;
    skip.add(member.id);
    out.push({ id: member.id, label: member.nickname, handle: null, member: true });
  }
  for (const person of Array.isArray(people) ? people : []) {
    if (skip.has(person.id)) continue;
    skip.add(person.id);
    out.push({ id: person.id, label: person.nickname || (person.handle ? `@${person.handle}` : ""), handle: person.handle ?? null, member: false });
  }
  return out.filter((option) => option.label !== "").slice(0, limit);
}

/** How a person in the list is named: their name, else their @handle. */
export function personName(person: PackageAudienceException["person"] | null | undefined): string | null {
  if (!person) return null;
  return person.nickname || (person.handle ? `@${person.handle}` : null);
}
