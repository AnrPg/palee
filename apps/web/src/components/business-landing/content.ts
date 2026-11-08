/**
 * What the business landing (palee.app/business, ADR-556) says to each
 * audience. Pure data: the components look the words up in the
 * `BusinessLanding` messages and the visuals by `visual`, so adding a feature
 * is one row here plus its copy.
 */

export const AUDIENCES = ["box", "coach"] as const;
export type Audience = (typeof AUDIENCES)[number];

/** `?for=coach` opens the page on the coach's side, so links can point at it. */
export function audienceFromParam(value: string | string[] | undefined | null): Audience {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw === "coach" ? "coach" : "box";
}

export type VisualId =
  | "schedule"
  | "receipt"
  | "checkin"
  | "website"
  | "ai"
  | "wod"
  | "timer"
  | "roles"
  | "club"
  | "stats"
  | "clients"
  | "coachPay"
  | "insights"
  | "fiscal"
  | "machines"
  | "staffPay"
  | "cleaning"
  | "stock"
  | "campaigns"
  | "offer"
  | "shop";

export type TileSpec = {
  /** Message key under `tiles.` (kicker, title, body). */
  id: string;
  visual: VisualId;
  /** Two columns from tablets up. */
  wide?: boolean;
  /** The whole row at every size. */
  full?: boolean;
  /** The dark tile style; at most one per row. */
  dark?: boolean;
  /** Marks the tile as on its way (it shows «Soon»). */
  soon?: boolean;
};

/**
 * What a box gets, in the order the bento shows it. The bento has 1 column on
 * phones, 2 on tablets and 4 from laptops up, and packs densely: the spans
 * are chosen so no size leaves a hole (`gridHoles`, tested).
 */
const BOX_FEATURES: TileSpec[] = [
  { id: "schedule", visual: "schedule", wide: true },
  { id: "payments", visual: "receipt", dark: true },
  { id: "checkin", visual: "checkin" },
  { id: "ai", visual: "ai", wide: true, dark: true },
  { id: "wod", visual: "wod" },
  { id: "club", visual: "club" },
  { id: "timer", visual: "timer", wide: true, dark: true },
  { id: "staff", visual: "roles", wide: true },
  { id: "stats", visual: "stats", full: true },
];

const COACH_FEATURES: TileSpec[] = [
  { id: "clients", visual: "clients", wide: true },
  { id: "programming", visual: "wod", dark: true },
  { id: "coachPayments", visual: "receipt" },
  { id: "squad", visual: "club" },
  { id: "ai", visual: "ai", wide: true, dark: true },
  { id: "coachPay", visual: "coachPay" },
  { id: "coachStats", visual: "stats", full: true },
];

/** The running of the business: what eats the owner's evenings. */
const BOX_MANAGEMENT: TileSpec[] = [
  { id: "analytics", visual: "insights", wide: true, dark: true },
  { id: "accounting", visual: "fiscal", wide: true },
  { id: "machines", visual: "machines" },
  { id: "staffPay", visual: "staffPay" },
  { id: "cleaning", visual: "cleaning" },
  { id: "stock", visual: "stock" },
  { id: "campaigns", visual: "campaigns", wide: true, soon: true },
  { id: "offers", visual: "offer", wide: true },
];

const COACH_MANAGEMENT: TileSpec[] = [
  { id: "coachAnalytics", visual: "insights", wide: true, dark: true },
  { id: "coachAccounting", visual: "fiscal", wide: true },
  { id: "coachCampaigns", visual: "campaigns", wide: true, soon: true },
  { id: "coachOffers", visual: "offer", wide: true },
];

export const FEATURES: Record<Audience, TileSpec[]> = { box: BOX_FEATURES, coach: COACH_FEATURES };
export const MANAGEMENT: Record<Audience, TileSpec[]> = { box: BOX_MANAGEMENT, coach: COACH_MANAGEMENT };

/** «See how it works»: one day, hour by hour. Message keys under `how.<audience>.<id>`. */
export const DAY: Record<Audience, { id: string; visual: VisualId }[]> = {
  box: [
    { id: "wod", visual: "wod" },
    { id: "full", visual: "schedule" },
    { id: "checkin", visual: "checkin" },
    { id: "payment", visual: "receipt" },
    { id: "timer", visual: "timer" },
    { id: "club", visual: "club" },
    { id: "close", visual: "stats" },
  ],
  coach: [
    { id: "week", visual: "wod" },
    { id: "video", visual: "clients" },
    { id: "payment", visual: "receipt" },
    { id: "scaling", visual: "ai" },
    { id: "squad", visual: "club" },
    { id: "insights", visual: "insights" },
  ],
};

/** Phones: the same story told as full-screen stories. Message keys under `stories.<audience>.<id>`. */
export const STORIES: Record<Audience, { id: string; visual: VisualId }[]> = {
  box: [
    { id: "hero", visual: "schedule" },
    { id: "website", visual: "website" },
    { id: "shop", visual: "shop" },
    { id: "ai", visual: "ai" },
    { id: "timer", visual: "timer" },
    { id: "checkin", visual: "checkin" },
    { id: "insights", visual: "insights" },
    { id: "club", visual: "club" },
    { id: "running", visual: "machines" },
    { id: "payments", visual: "receipt" },
    { id: "demo", visual: "roles" },
  ],
  coach: [
    { id: "hero", visual: "clients" },
    { id: "website", visual: "website" },
    { id: "shop", visual: "shop" },
    { id: "programming", visual: "wod" },
    { id: "ai", visual: "ai" },
    { id: "insights", visual: "insights" },
    { id: "squad", visual: "club" },
    { id: "payments", visual: "receipt" },
    { id: "demo", visual: "coachPay" },
  ],
};

/** «What each one gets»: message key under `compare.rows`, then box and coach. */
export const COMPARISON: { id: string; box: boolean; coach: boolean }[] = [
  { id: "classes", box: true, coach: false },
  { id: "packages", box: true, coach: true },
  { id: "programming", box: true, coach: true },
  { id: "payments", box: true, coach: true },
  { id: "accounting", box: true, coach: true },
  { id: "website", box: true, coach: true },
  { id: "ai", box: true, coach: true },
  { id: "analytics", box: true, coach: true },
  { id: "offers", box: true, coach: true },
  { id: "staff", box: true, coach: false },
  { id: "staffPay", box: true, coach: false },
  { id: "facility", box: true, coach: false },
  { id: "timer", box: true, coach: false },
  { id: "community", box: true, coach: true },
];

/** Columns of the bento at each size (Tailwind: base, `md`, `lg`). */
export const GRID_COLUMNS = [1, 2, 4] as const;

/** How many columns a tile takes in a grid of `columns`. */
export function tileSpan(tile: Pick<TileSpec, "wide" | "full">, columns: number) {
  if (tile.full) return columns;
  return tile.wide ? Math.min(2, columns) : 1;
}

/**
 * Empty cells a densely packed grid of `columns` would leave (CSS
 * `grid-auto-flow: dense`, one row high tiles). Zero means the bento is
 * filled edge to edge at that size.
 */
export function gridHoles(tiles: Pick<TileSpec, "wide" | "full">[], columns: number) {
  const rows: number[][] = [];
  for (const tile of tiles) {
    const span = tileSpan(tile, columns);
    let placed = false;
    for (const row of rows) {
      const used = row.reduce((sum, value) => sum + value, 0);
      if (used + span <= columns) {
        row.push(span);
        placed = true;
        break;
      }
    }
    if (!placed) rows.push([span]);
  }
  return rows.reduce((holes, row) => holes + columns - row.reduce((sum, value) => sum + value, 0), 0);
}
