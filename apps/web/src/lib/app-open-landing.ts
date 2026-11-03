// W7 screen 12 (ANR): a member of exactly one box lands on the Box tab when
// the app opens; everyone else lands on Feed. Only the first screen of an app
// open is decided: tapping Feed later always shows Feed.

let firstPath: string | null = null;
let decided = false;

/** Records a route the app shows; any route after the first one ends the "app open". */
export function noteRoute(pathname: string) {
  if (firstPath === null) firstPath = pathname;
  else if (pathname !== firstPath) decided = true;
}

/**
 * Whether this is the app-open decision for `pathname`: true once, and only
 * when `pathname` is the first route of this page load.
 */
export function claimAppOpenLanding(pathname: string): boolean {
  if (decided) return false;
  if (firstPath === null) firstPath = pathname;
  decided = true;
  return firstPath === pathname;
}

/** Where the app opens instead of Feed, or null to stay on Feed. */
export function appOpenLanding(input: { membershipCount: number; vendor: boolean }): "/box" | null {
  return !input.vendor && input.membershipCount === 1 ? "/box" : null;
}

/** Tests only: start a new page load. */
export function resetAppOpenLanding() {
  firstPath = null;
  decided = false;
}
