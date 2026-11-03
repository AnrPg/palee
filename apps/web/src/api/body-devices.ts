import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// v3.2 «Body and devices» (ADR-374..377): the previous attempt's pace line,
// the watch, barcode foods in meals, and belts and levels.

type Json<T> = T extends { content: { "application/json": infer Body } }
  ? Body
  : never;
type Op = operations;

export type Pacer = Json<
  Op["PaleeWeb.ExecutionPacerController.show"]["responses"][200]
>["pacer"];
export type PaceCheckpoint = Pacer["checkpoints"][number];
export type PaceSection = Pacer["sections"][number];

export type WatchList = Json<
  Op["PaleeWeb.WatchController.index"]["responses"][200]
>;
export type PairedWatch = WatchList["watches"][number];
export type WatchPlatform = PairedWatch["platform"];
export type WatchSettings = PairedWatch["settings"];
export type WatchOffer = Json<
  Op["PaleeWeb.WatchController.offer"]["responses"][200]
>;
export type WatchOfferAnswer = Json<
  Op["PaleeWeb.WatchController.answer_offer"]["responses"][200]
>;

export type BarcodeLookup = Json<
  Op["PaleeWeb.FoodsController.barcode"]["responses"][200]
>;
export type Food = NonNullable<BarcodeLookup["food"]>;
export type FoodPortion = NonNullable<Food["portion_hint"]>;
export type CustomFoodInput = Json<
  NonNullable<Op["PaleeWeb.FoodsController.create"]["requestBody"]>
>;
export type FoodResponse = Json<
  Op["PaleeWeb.FoodsController.update"]["responses"][200]
>;

export type RankLadders = Json<
  Op["PaleeWeb.AdminRankLaddersController.index"]["responses"][200]
>;
export type RankLadder = RankLadders["ladders"][number];
export type Rank = RankLadder["ranks"][number];
export type RankColor = NonNullable<Rank["color"]>;
export type RankLadderInput = Json<
  NonNullable<Op["PaleeWeb.AdminRankLaddersController.create"]["requestBody"]>
>;
export type RankStandings = Json<
  Op["PaleeWeb.MyRanksController.index"]["responses"][200]
>;
export type RankStanding = RankStandings["ladders"][number];
export type RankAward = RankStanding["history"][number];
export type RankAwardInput = Json<
  NonNullable<Op["PaleeWeb.StaffRanksController.award"]["requestBody"]>
>;

const org = (slug: string) => `/org/${encodeURIComponent(slug)}`;
const id = (value: string) => encodeURIComponent(value);

// A malformed answer (an older server, a proxy page) reads as an empty list, never a crash.
function withList<T extends object, K extends keyof T>(
  body: T | null | undefined,
  key: K,
): T {
  const value = body && typeof body === "object" ? body[key] : undefined;
  return { ...(body ?? {}), [key]: Array.isArray(value) ? value : [] } as T;
}

export const pacerKey = (executionId: string) =>
  ["body-devices", "pacer", executionId] as const;
export const WATCHES_KEY = ["body-devices", "watches"] as const;
export const rankLaddersKey = (slug: string) =>
  ["body-devices", "rank-ladders", slug] as const;
export const myRanksKey = (slug: string) =>
  ["body-devices", "my-ranks", slug] as const;
export const clientRanksKey = (slug: string, userId: string) =>
  ["body-devices", "client-ranks", slug, userId] as const;

// ADR-374: race your past self.
export function fetchPacer(token: string, executionId: string) {
  return apiRequest<{ pacer: Pacer }>(`/executions/${id(executionId)}/pacer`, {
    token,
  }).then((body) => body.pacer);
}

// ADR-375: the watch (pairing happens in the phone app; the web shows and changes settings).
export function fetchWatches(token: string) {
  return apiRequest<WatchList>("/me/devices/watches", { token }).then((body) =>
    withList(body, "watches"),
  );
}

export function saveWatchSettings(
  token: string,
  watch: PairedWatch,
  settings: Partial<WatchSettings>,
) {
  return apiRequest<{ watch: PairedWatch }>(
    `/me/devices/watches/${id(watch.platform)}`,
    {
      method: "PUT",
      token,
      body: { contract_version: watch.contract_version, settings },
    },
  ).then((body) => body.watch);
}

export function unpairWatch(token: string, platform: WatchPlatform) {
  return apiRequest<void>(`/me/devices/watches/${id(platform)}`, {
    method: "DELETE",
    token,
  });
}

/** ANR's D8 rules: asked only when a WOD is opened for execution with a connected watch. */
export function requestWatchOffer(
  token: string,
  executionId: string,
  platform: WatchPlatform,
  watchConnected: boolean,
) {
  return apiRequest<WatchOffer>(`/executions/${id(executionId)}/watch-offer`, {
    method: "POST",
    token,
    body: { platform, watch_connected: watchConnected },
  });
}

export function answerWatchOffer(
  token: string,
  executionId: string,
  answer: "yes" | "no",
) {
  return apiRequest<WatchOfferAnswer>(
    `/executions/${id(executionId)}/watch-offer/answer`,
    {
      method: "PUT",
      token,
      body: { answer },
    },
  );
}

// ADR-376: barcode foods and own foods.
export function lookUpBarcode(token: string, barcode: string) {
  return apiRequest<BarcodeLookup>(`/me/foods/barcode/${id(barcode)}`, {
    token,
  });
}

export function createCustomFood(token: string, food: CustomFoodInput) {
  return apiRequest<FoodResponse>("/me/foods", {
    method: "POST",
    token,
    body: food,
  }).then((body) => body.food);
}

// ADR-377: belts and levels.
export function fetchRankLadders(token: string, slug: string) {
  return apiRequest<RankLadders>(`${org(slug)}/admin/rank-ladders`, {
    token,
  }).then((body) => withList(body, "ladders"));
}

export function createRankLadder(
  token: string,
  slug: string,
  body: RankLadderInput,
) {
  return apiRequest<{ ladder: RankLadder }>(`${org(slug)}/admin/rank-ladders`, {
    method: "POST",
    token,
    body,
  }).then((response) => response.ladder);
}

export function updateRankLadder(
  token: string,
  slug: string,
  ladderId: string,
  body: RankLadderInput,
) {
  return apiRequest<{ ladder: RankLadder }>(
    `${org(slug)}/admin/rank-ladders/${id(ladderId)}`,
    {
      method: "PUT",
      token,
      body,
    },
  ).then((response) => response.ladder);
}

export function deleteRankLadder(
  token: string,
  slug: string,
  ladderId: string,
) {
  return apiRequest<void>(`${org(slug)}/admin/rank-ladders/${id(ladderId)}`, {
    method: "DELETE",
    token,
  });
}

export function fetchMyRanks(token: string, slug: string) {
  return apiRequest<RankStandings>(`${org(slug)}/me/ranks`, { token }).then(
    (body) => withList(body, "ladders"),
  );
}

export function fetchClientRanks(token: string, slug: string, userId: string) {
  return apiRequest<RankStandings>(
    `${org(slug)}/staff/clients/${id(userId)}/ranks`,
    { token },
  ).then((body) => withList(body, "ladders"));
}

export function awardRank(
  token: string,
  slug: string,
  userId: string,
  body: RankAwardInput,
) {
  return apiRequest<{ award: RankAward }>(
    `${org(slug)}/staff/clients/${id(userId)}/ranks`,
    {
      method: "POST",
      token,
      body,
    },
  ).then((response) => response.award);
}

export function revokeRankAward(
  token: string,
  slug: string,
  awardId: string,
  reason: string,
) {
  return apiRequest<{ award: RankAward }>(
    `${org(slug)}/staff/rank-awards/${id(awardId)}/revoke`,
    {
      method: "POST",
      token,
      body: { reason },
    },
  ).then((response) => response.award);
}

export function fetchMyDiploma(token: string, slug: string, awardId: string) {
  return apiRequest<Blob>(
    `${org(slug)}/me/ranks/awards/${id(awardId)}/certificate`,
    { token, responseType: "blob" },
  );
}

export function fetchClientDiploma(
  token: string,
  slug: string,
  awardId: string,
) {
  return apiRequest<Blob>(
    `${org(slug)}/staff/rank-awards/${id(awardId)}/certificate`,
    { token, responseType: "blob" },
  );
}
