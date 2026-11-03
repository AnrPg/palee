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
- Writing label reads into the shared cache: they are personal data and
  would mix with ODbL rows; kept private.
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
- Open questions: a reuse licence for the posokanei product list; an
  explicit choice to share a label-read food with all members (and OFF);
  whether a member-level AI switch is wanted for label reading.

## Implementation Notes
- `Places.home_country/1` (new `HomeAreaStore.country/1`) gives the miss
  country in the person's own session.
- dev: `FOOD_DATABASE=open_food_facts` or `chain` asks the real chain;
  otherwise the sandbox catalogue.
- Tests: Req.Test stubs per adapter (`Palee.OpenFoodFacts`,
  `Palee.UsdaFoodDataCentral`), the chain's order, timeouts, budget and
  skipping; `Palee.FakeFoodLabelReader` for the endpoint.
