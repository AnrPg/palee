import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// v3.2 «Body and devices» (ADR-374..377): the previous attempt's pace line,
// the watch, barcode foods in meals, and belts and levels.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Op = operations;

export type Pacer = Json<Op["PaleeWeb.ExecutionPacerController.show"]["responses"][200]>["pacer"];
export type PaceCheckpoint = Pacer["checkpoints"][number];
export type PaceSection = Pacer["sections"][number];

export type WatchList = Json<Op["PaleeWeb.WatchController.index"]["responses"][200]>;
export type PairedWatch = WatchList["watches"][number];
export type WatchPlatform = PairedWatch["platform"];
export type WatchSettings = PairedWatch["settings"];
export type WatchOffer = Json<Op["PaleeWeb.WatchController.offer"]["responses"][200]>;
export type WatchOfferAnswer = Json<Op["PaleeWeb.WatchController.answer_offer"]["responses"][200]>;

export type BarcodeLookup = Json<Op["PaleeWeb.FoodsController.barcode"]["responses"][200]>;
export type Food = NonNullable<BarcodeLookup["food"]>;
export type FoodPortion = NonNullable<Food["portion_hint"]>;
export type CustomFoodInput = Json<NonNullable<Op["PaleeWeb.FoodsController.create"]["requestBody"]>>;
export type FoodResponse = Json<Op["PaleeWeb.FoodsController.update"]["responses"][200]>;
export type FoodLabelReading = Json<Op["PaleeWeb.FoodsController.read_label"]["responses"][200]>;
export type FoodLabelPrefill = FoodLabelReading["food"];
export type BarcodeMisses = Json<Op["PaleeWeb.PlatformFoodMissesController.index"]["responses"][200]>;
export type BarcodeMiss = BarcodeMisses["misses"][number];

export type RankLadders = Json<Op["PaleeWeb.AdminRankLaddersController.index"]["responses"][200]>;
export type RankLadder = RankLadders["ladders"][number];
export type Rank = RankLadder["ranks"][number];
export type RankColor = NonNullable<Rank["color"]>;
export type RankLadderInput = Json<NonNullable<Op["PaleeWeb.AdminRankLaddersController.create"]["requestBody"]>>;
export type RankStandings = Json<Op["PaleeWeb.MyRanksController.index"]["responses"][200]>;
export type RankStanding = RankStandings["ladders"][number];
export type RankAward = RankStanding["history"][number];
export type RankAwardInput = Json<NonNullable<Op["PaleeWeb.StaffRanksController.award"]["requestBody"]>>;
export type RankProgress = NonNullable<RankStanding["progress"]>;
export type RankCriterion = RankLadder["ready_criteria"][number];
export type RankSkillCheckInput = Json<NonNullable<Op["PaleeWeb.StaffRanksController.check_skill"]["requestBody"]>>;
export type ClassSkills = Json<Op["PaleeWeb.StaffRanksController.class_skills"]["responses"][200]>;
export type ClassSkillPerson = ClassSkills["people"][number];
export type RankSkillBatchInput = Json<NonNullable<Op["PaleeWeb.StaffRanksController.batch_skills"]["requestBody"]>>;
export type RankSkillBatchResult = Json<Op["PaleeWeb.StaffRanksController.batch_skills"]["responses"][200]>;
export type ReadyForRank = Json<Op["PaleeWeb.StaffRanksController.ready"]["responses"][200]>["people"][number];

const org = (slug: string) => `/org/${encodeURIComponent(slug)}`;
const id = (value: string) => encodeURIComponent(value);

// A malformed answer (an older server, a proxy page) reads as an empty list, never a crash.
function withList<T extends object, K extends keyof T>(body: T | null | undefined, key: K): T {
  const value = body && typeof body === "object" ? body[key] : undefined;
  return { ...(body ?? {}), [key]: Array.isArray(value) ? value : [] } as T;
}

export const pacerKey = (executionId: string) => ["body-devices", "pacer", executionId] as const;
export const WATCHES_KEY = ["body-devices", "watches"] as const;
export const rankLaddersKey = (slug: string, locale?: string) =>
  (locale ? ["body-devices", "rank-ladders", slug, locale] : ["body-devices", "rank-ladders", slug]) as readonly string[];
export const myRanksKey = (slug: string) => ["body-devices", "my-ranks", slug] as const;
export const classSkillsKey = (slug: string, userIds: readonly string[]) => ["body-devices", "class-skills", slug, ...userIds] as const;
export const readyRanksKey = (slug: string) => ["body-devices", "ready-ranks", slug] as const;
export const clientRanksKey = (slug: string, userId: string) => ["body-devices", "client-ranks", slug, userId] as const;

// ADR-374: race your past self.
export function fetchPacer(token: string, executionId: string) {
  return apiRequest<{ pacer: Pacer }>(`/executions/${id(executionId)}/pacer`, { token }).then((body) => body.pacer);
}

// ADR-375: the watch (pairing happens in the phone app; the web shows and changes settings).
export function fetchWatches(token: string) {
  return apiRequest<WatchList>("/me/devices/watches", { token }).then((body) => withList(body, "watches"));
}

export function saveWatchSettings(token: string, watch: PairedWatch, settings: Partial<WatchSettings>) {
  return apiRequest<{ watch: PairedWatch }>(`/me/devices/watches/${id(watch.platform)}`, {
    method: "PUT",
    token,
    body: { contract_version: watch.contract_version, settings },
  }).then((body) => body.watch);
}

export function unpairWatch(token: string, platform: WatchPlatform) {
  return apiRequest<void>(`/me/devices/watches/${id(platform)}`, { method: "DELETE", token });
}

/** ANR's D8 rules: asked only when a WOD is opened for execution with a connected watch. */
export function requestWatchOffer(token: string, executionId: string, platform: WatchPlatform, watchConnected: boolean) {
  return apiRequest<WatchOffer>(`/executions/${id(executionId)}/watch-offer`, {
    method: "POST",
    token,
    body: { platform, watch_connected: watchConnected },
  });
}

export function answerWatchOffer(token: string, executionId: string, answer: "yes" | "no") {
  return apiRequest<WatchOfferAnswer>(`/executions/${id(executionId)}/watch-offer/answer`, {
    method: "PUT",
    token,
    body: { answer },
  });
}

// ADR-376: barcode foods and own foods.
export function lookUpBarcode(token: string, barcode: string) {
  return apiRequest<BarcodeLookup>(`/me/foods/barcode/${id(barcode)}`, { token });
}

export function createCustomFood(token: string, food: CustomFoodInput) {
  return apiRequest<FoodResponse>("/me/foods", { method: "POST", token, body: food }).then((body) => body.food);
}

// ADR-421: «Φωτογραφία ετικέτας» prefills the own food; the photos are not kept.
export function readFoodLabel(token: string, photos: { front?: Blob | null; nutrition?: Blob | null }) {
  const form = new FormData();
  if (photos.front) form.append("front", photos.front, "front");
  if (photos.nutrition) form.append("nutrition", photos.nutrition, "nutrition");
  return apiRequest<FoodLabelReading>("/me/foods/label-read", { method: "POST", token, body: form }).then((body) => ({
    macros_visible: body?.macros_visible === true,
    food: {
      name: body?.food?.name ?? null,
      brand: body?.food?.brand ?? null,
      serving_label: body?.food?.serving_label ?? null,
      portion_hint: body?.food?.portion_hint ?? null,
      nutrients: body?.food?.nutrients ?? null,
    },
  }));
}

// ADR-421: barcodes no source had (platform console).
export function fetchBarcodeMisses(token: string, country?: string | null) {
  const query = country ? `?country=${encodeURIComponent(country)}` : "";
  return apiRequest<BarcodeMisses>(`/platform/food-misses${query}`, { token }).then((body) =>
    Array.isArray(body?.misses) ? body.misses : [],
  );
}

// ADR-377: belts and levels.
export type RankTemplate = RankLadders["templates"][number];

/** The box's ladders and the template catalogue in `locale` (ADR-400); a malformed list reads as empty. */
export function fetchRankLadders(token: string, slug: string, locale?: string) {
  const query = locale ? `?locale=${encodeURIComponent(locale)}` : "";
  return apiRequest<RankLadders>(`${org(slug)}/admin/rank-ladders${query}`, { token }).then((body) =>
    withList(withList(withList(body, "ladders"), "templates"), "box_disciplines"),
  );
}

export function createRankLadder(token: string, slug: string, body: RankLadderInput) {
  return apiRequest<{ ladder: RankLadder }>(`${org(slug)}/admin/rank-ladders`, { method: "POST", token, body }).then(
    (response) => response.ladder,
  );
}

export function updateRankLadder(token: string, slug: string, ladderId: string, body: RankLadderInput) {
  return apiRequest<{ ladder: RankLadder }>(`${org(slug)}/admin/rank-ladders/${id(ladderId)}`, {
    method: "PUT",
    token,
    body,
  }).then((response) => response.ladder);
}

export function deleteRankLadder(token: string, slug: string, ladderId: string) {
  return apiRequest<void>(`${org(slug)}/admin/rank-ladders/${id(ladderId)}`, { method: "DELETE", token });
}

export function fetchMyRanks(token: string, slug: string) {
  return apiRequest<RankStandings>(`${org(slug)}/me/ranks`, { token }).then((body) => withList(body, "ladders"));
}

export function fetchClientRanks(token: string, slug: string, userId: string) {
  return apiRequest<RankStandings>(`${org(slug)}/staff/clients/${id(userId)}/ranks`, { token }).then((body) =>
    withList(body, "ladders"),
  );
}

export function awardRank(token: string, slug: string, userId: string, body: RankAwardInput) {
  return apiRequest<{ award: RankAward }>(`${org(slug)}/staff/clients/${id(userId)}/ranks`, {
    method: "POST",
    token,
    body,
  }).then((response) => response.award);
}

/** Ticks (or unticks) one skill for a client; the answer is their standing. */
export function checkRankSkill(token: string, slug: string, userId: string, body: RankSkillCheckInput) {
  return apiRequest<RankStandings>(`${org(slug)}/staff/clients/${id(userId)}/ranks/skills`, { method: "PUT", token, body }).then((answer) =>
    withList(answer, "ladders"),
  );
}

/** A class's people: the ladders' skills, what each works towards and has ticked (mockup 3B). */
export function fetchClassSkills(token: string, slug: string, userIds: readonly string[]) {
  const query = `?user_ids=${encodeURIComponent(userIds.join(","))}`;
  return apiRequest<ClassSkills>(`${org(slug)}/staff/ranks/skills/batch${query}`, { token }).then((body) =>
    withList(withList(body, "ladders"), "people"),
  );
}

export function batchRankSkill(token: string, slug: string, body: RankSkillBatchInput) {
  return apiRequest<RankSkillBatchResult>(`${org(slug)}/staff/ranks/skills/batch`, { method: "PUT", token, body }).then((answer) =>
    withList(withList(answer, "updated"), "skipped"),
  );
}

/** «Πληροί τις προϋποθέσεις»: people who meet what their ladder counts (the coach decides). */
export function fetchReadyRanks(token: string, slug: string) {
  return apiRequest<{ people: ReadyForRank[] }>(`${org(slug)}/staff/ranks/ready`, { token }).then(
    (body) => withList(body, "people").people,
  );
}

export function revokeRankAward(token: string, slug: string, awardId: string, reason: string) {
  return apiRequest<{ award: RankAward }>(`${org(slug)}/staff/rank-awards/${id(awardId)}/revoke`, {
    method: "POST",
    token,
    body: { reason },
  }).then((response) => response.award);
}

export function fetchMyDiploma(token: string, slug: string, awardId: string) {
  return apiRequest<Blob>(`${org(slug)}/me/ranks/awards/${id(awardId)}/certificate`, { token, responseType: "blob" });
}

export function fetchClientDiploma(token: string, slug: string, awardId: string) {
  return apiRequest<Blob>(`${org(slug)}/staff/rank-awards/${id(awardId)}/certificate`, { token, responseType: "blob" });
}
