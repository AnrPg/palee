# ADR-421: More free food sources, a photo of the label, and barcodes nobody had
Date: 2026-11-03
Status: Accepted

## Context
ADR-376 looks barcodes up in Open Food Facts (OFF) only. The product owner
(2026-11-03): "implement them now in v3.2. skip paid vendor for now. we need
the nutrition table to keep track of macros (if user/coach activated it) …
also, find API for greek products as well". Research with sources and
licences: `docs/research/food-sources-research-2026-11-03.md`.

## Decision
- **Order of a scan** (`Application.Foods.barcode/3`): (a) Palee's own store
  — the person's own food with that barcode, then the cache of public
  products (`food_products`); (b) OFF; (c) USDA FoodData Central Branded
  Foods; (d) licensed product lists (the Greek source). Other members' own
  foods are never used: they are personal data (vision §4.5).
- **Chain** `Infrastructure.Nutrition.ChainFoodDatabase` is the
  `FoodDatabase` adapter in production (config `:food_chain`): sources
  `[{module, timeout_ms}]` (OFF 3 s, USDA 2.5 s, lists 1 s) inside a 5 s
  total budget. Each source runs in a task cut off at its timeout or the
  budget; a crash is caught. First `{:ok, _}` wins; `:not_configured` is
  skipped; all "not found" → not found; any transient failure → transient,
  so the outbox (ADR-376) retries instead of believing a miss for 7 days.
- **USDA** `UsdaFoodDataCentralClient`: `POST /fdc/v1/foods/search`
  (`dataType: Branded`), only an item whose `gtinUpc` is the same GTIN
  (leading zeros ignored); nutrients per 100 g by nutrient number, sodium →
  salt × 2.5; never energy. Key `USDA_FDC_API_KEY` (free, api.data.gov);
  without it the source answers `:not_configured`. CC0, credited.
- **Greek source** `EctoFoodCatalogue` over `food_catalogue_products`
  (list, barcode, name, brand, size, the list's source name and licence).
  No Greek source publishes barcodes for reuse today (posokanei.gov.gr /
  e-katanalotis has no API or dataset; Verified by GS1 is 30 queries a day
  free, members only beyond). A list Palee obtains under a licence is loaded
  with `mix palee.food_catalogue.import FILE --list … --source … --licence …`.
  Empty table → "not found" at once. Name, brand and size only.
- **One source per cached row**: `food_products.source` is set from the
  answer (`open_food_facts`, `usda_fdc`, `catalogue`) and the new
  `attribution` column keeps a list's own credit. `FoodCachePolicy.attribution/3`
  credits by source; the API's `attribution` now allows a null
  `images_licence`/`url`. Cache rules (30/7 days, back-off) are unchanged.
- **Barcodes nobody had** (`food_barcode_misses`): one row per barcode and
  country (ISO alpha-2 of the person's main «Η περιοχή μου», else empty),
  scan count, first and last day. Counted on every scan that ends in the
  manual entry with `not_found` (not shop codes, not failures, not own
  foods). No person, box or time of day. Platform console
  `GET /api/platform/food-misses[?country=GR]` (vendors), page
  «Barcode χωρίς προϊόν» at `/platform/food-misses`, top 200.
- **«Φωτογραφία ετικέτας»** (`POST /api/me/foods/label-read`, multipart
  `front` and/or `nutrition`, JPEG/PNG/WebP ≤ 4 MB, the AI suggestion rate
  limit): port `Nutrition.Ports.FoodLabelReader`, adapter
  `GeminiFoodLabelReader` over the platform vision call (`GeminiVision`,
  ADR-157, now taking several images; metered per ADR-152 as feature
  `food_label`, no gym). The model returns name, brand, portion and the
  table per 100 g and per portion; `Nutrition.Domain.FoodLabel` keeps six
  nutrients per 100 g (per-portion values converted when the portion's
  grams are printed; anything outside 0–100 dropped; energy never taken).
  The answer prefills «Δικό μου τρόφιμο»; nothing is saved until the member
  saves it, and it stays theirs (`custom_foods`). Numbers follow
  `NutrientDisclosure` as everywhere. Photos are re-encoded in the browser
  (no EXIF), read in memory and never stored. Without `GEMINI_API_KEY` the
  barcode answer says `label_reading: false` and the action is hidden.
- **Own food form**: under «Προχωρημένα», the six grams per 100 g appear
  when macros may show (a plan sets them and they are not hidden), each
  checked 0–100 with the error under its field.

## Rationale
Free and open sources first, in coverage order for a Greek user (OFF is the
best open source for Greek products); USDA adds imported/US brands at no
cost. The import adapter is the only legal way to add a Greek list without
an API. Per-source timeouts and a budget keep the scan bounded; the outbox
already handles retries. The label photo fills the nutrition gap the Greek
sources cannot, without sharing anyone's data.

## Alternatives Considered
- Scraping posokanei.gov.gr or retailer sites: no licence; rejected.
- GS1 Greece / Verified by GS1 API: paid membership; rejected for now.
- Paid vendors (e.g. Nutritionix, Edamam): excluded by the product owner.
- Running sources in parallel: faster, but would ask every source for every
  barcode (OFF's limit is 15 reads/min/IP); the order also decides which
  source a row comes from.
- Writing label reads into the shared cache by default: they are personal
  data and would mix with ODbL rows; kept private unless the member
  explicitly shares (addendum below).
- The gym's own AI key (ADR-174): meals are the person's, not the gym's;
  the platform key is used as for alt text (ADR-157).

## Consequences
- ODbL: the cache stays private; publishing it (e.g. through ADR-378)
  would require offering the OFF-derived rows under ODbL. One source per
  row keeps that a filter.
- OFF's published limit is 15 product reads/min/IP (not 100 as ADR-376
  noted); the adapter note is corrected.
- New env var `USDA_FDC_API_KEY`. Migration
  `20270625100000_food_sources_and_barcode_misses`.
- Open questions: a reuse licence for the posokanei product list; whether
  a member-level AI switch is wanted for label reading. (Sharing a
  label-read food with everyone: decided, addendum below.)

## Implementation Notes
- `Places.home_country/1` (new `HomeAreaStore.country/1`) gives the miss
  country in the person's own session.
- dev: `FOOD_DATABASE=open_food_facts` or `chain` asks the real chain;
  otherwise the sandbox catalogue.
- Tests: Req.Test stubs per adapter (`Palee.OpenFoodFacts`,
  `Palee.UsdaFoodDataCentral`), the chain's order, timeouts, budget and
  skipping; `Palee.FakeFoodLabelReader` for the endpoint.

## Addendum (2026-11-03): «Μοιράσου το», sharing an own food with everyone
Product owner (2026-11-03): one explicit opt-in in «Δικό μου τρόφιμο» to
share the product with all Palee members and with Open Food Facts. Own foods
are still private by default; they reach others **only when the member
explicitly shares**.

- **The choice**: one checkbox, never pre-ticked, «Μοιράσου το με όλους στο
  Palee και στο Open Food Facts», with one line on what is shared. Shown only
  for a product barcode (not without one, not a shop's own code); the API
  answers `share_needs_barcode` (422) otherwise. `share: true` on
  `POST /api/me/foods` or `PATCH /api/me/foods/:id`; the food's
  `shared_at` records it. Unticked foods behave exactly as before.
- **What is shared**: barcode, name, brand, portion («Μερίδα»), the suggested
  hand portion and the six nutrients per 100 g the member saved. Never the
  member (id, name), a meal, the note, or a photo.
- **Palee's public cache**: a `food_products` row with source
  `palee_members` (attribution «Palee members», ODbL 1.0, the licence of the
  same data at OFF), so the next scan by anyone finds it. Written atomically
  only where no source has the product (no row, `not_found`, or a lookup
  that found nothing yet): a product from OFF, USDA or a list, a stale one
  being refreshed and an earlier share are never overwritten; **the first
  share wins**. The 30-day refresh still asks the chain: a public source
  that has it by then replaces the members' row; a miss keeps it.
  The web shows «από μέλη» next to the source line.
- **Audit and outbox** (`food_product_shares`, one row per barcode): what was
  shared, `shared_at`, and `user_id` (who shared, for abuse handling only;
  never shown or sent; set to null when the account is deleted, and nulled
  by the foreign key if the user row goes). No RLS, like `food_products`:
  written and read only by the platform (request path and worker), never in
  a tenant session.
- **Open Food Facts** (`Nutrition.Ports.FoodContributor`,
  `OpenFoodFactsContributor`): the official write API
  `POST /cgi/product_jqm2.pl` (form fields `code`, `user_id`, `password`,
  `lang`, `product_name_<lang>`, `brands`, `serving_size`,
  `nutrition_data_per=100g`, `nutriment_<x>` + `_unit=g`, `comment`,
  `app_name`, `app_version`, `app_uuid`) with Palee's own OFF account
  (`OFF_USER_ID`, `OFF_PASSWORD`, a "global app account" as OFF allows;
  OAuth is not offered yet) and the same User-Agent as reads. `app_uuid` is
  an HMAC pseudonym per member (OFF asks for it so its moderators can stop
  one contributor without banning the app); it cannot be turned back into
  the member. Before writing, the product is read once; if OFF has it the
  share ends `exists` and nothing is written there either.
  `LookUpFoodsJob` (every 5 min) sends at most 10 due shares a run, which
  keeps the existence reads far under 15/min/IP (OFF publishes no write
  limit). Network errors, 429 and 5xx back off 1/5/30/60 min up to 6
  attempts; other 4xx and `status: 0` are final (`failed`). Without the
  account the worker sends nothing and shares wait as `queued` (the
  member's consent stands; they go once the account is set), while Palee's
  cache already has them.
- **No photos to OFF**: OFF does not require one (its docs: photos are one
  way to add data, not a requirement), Palee never keeps the label photos
  (ADR-421 above), and sending them would mean storing them and licensing
  the member's pictures under CC BY-SA. Data only.
- **ODbL**: the members' rows are contributed to OFF under ODbL/DbCL; the
  cache remains one source per row (`palee_members` is a filter).
- Privacy policy: new item «Τρόφιμα που μοιράζεσαι» (`dataFoodShares`).
- Migration `20270703200000_food_product_shares` (`custom_foods.shared_at`,
  `food_product_shares`). Env: `OFF_USER_ID`, `OFF_PASSWORD` (production),
  optional `OFF_APP_UUID_SALT`, `OFF_WRITE_BASE_URL` (staging
  `https://world.openfoodfacts.net`, basic auth `off:off` added).
- Sources (read 2026-11-03):
  <https://openfoodfacts.github.io/openfoodfacts-server/api/>,
  <https://openfoodfacts.github.io/documentation/docs/Product-Opener/v2/products/post-cgi-product_jqm2.pl/>.
