# ADR-376: Barcode in meals — Open Food Facts, own foods, no counting
Date: 2026-10-31
Status: Accepted

## Context
CP-D9 (P2): scanning a product in the food log (BTWB). Vision §4.10 and §8.6
(«do no harm»): no calories shown to members, macros only when a coach's plan
sets them and they can be hidden (`hide_macros`). Meals (ADR-159) record hand
portions, never weights or calories.

## Decision
- **Lookup** (`GET /api/me/foods/barcode/:barcode`): EAN-13/EAN-8/UPC-A/GTIN-14
  with the GS1 check digit (`Nutrition.Domain.Barcode`); shop-printed codes
  (prefixes 02, 20–29) go straight to the manual entry. Order: the person's
  own food with that barcode → the cache → Open Food Facts.
- **Port** `Nutrition.Ports.FoodDatabase`: `OpenFoodFactsClient` (API v2,
  only the needed fields, a User-Agent naming Palee and a contact, Req with
  `req_options` from config) and `SandboxFoodDatabase` (dev and tests).
- **Cache and outbox** (`food_products`, platform table, no personal data,
  no tenant): found → 30 days then served stale while a refresh is queued;
  not found → 7 days; failures back off 1/5/30/60 min up to 6 attempts. One
  inline attempt when the request can claim the row (`FOR UPDATE SKIP
  LOCKED`); otherwise `pending` and `LookUpFoodsJob` (every 5 min) retries.
  Who scanned what is never stored.
- **What we keep of a product**: name (person's language first), first brand,
  quantity, serving, front image URL, categories, and per 100 g protein,
  carbohydrates, fat, fibre, sugars, salt. **Energy is never stored.**
- **What a member sees** (`NutrientDisclosure`): name, brand, picture and a
  **suggested hand portion** (`PortionHint`: vegetables by category, else
  the macro giving ≥ 40 % of energy); grams only when a plan of theirs sets
  macros and `hide_macros` is off.
- **Own foods** («Δικά μου τρόφιμα», `custom_foods`, personal): the manual
  fallback (name, optional barcode, serving label, optional grams, portion);
  never contributed to Open Food Facts.
- **Meals** gain an optional `foods` list (up to 10 `{name, barcode?,
  custom_food_id?, portion?}`), a name snapshot.
- **Licences**: Open Food Facts data is ODbL 1.0, images CC BY-SA. Every
  product shown carries `attribution` (source, licence, product link). The
  cache is an unmodified extract; if Palee ever publishes it or adds to it,
  that derived database is offered under ODbL (share-alike). Own foods are a
  separate database and never mixed into the cache.

## Rationale
The barcode helps the hand-portion habit instead of turning meals into a
calorie counter, which is the only form that passes §4.10.

## Alternatives Considered
- A commercial database (Nutritionix, FatSecret): per-call cost and
  calorie-first data. Not now; the port allows it.
- Storing energy and hiding it in the UI: data we must never show is data we
  should not hold.

## Consequences
- The scan button lives only inside the meal entry, hidden when the person
  has turned meals off; mockups in the W9 board.
- `custom_foods` is in the GDPR export and deleted with the account.

## Implementation Notes
- Migration `20270602300000`; `Palee.Application.Foods`, `FoodsController`,
  `Workers.LookUpFoodsJob`; config `:food_database`, `:open_food_facts`.
