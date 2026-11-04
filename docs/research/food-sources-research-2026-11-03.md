# Food sources by barcode: research (2026-11-03)

Context: ADR-376 looks barcodes up in Open Food Facts only. The product owner
asked (2026-11-03) for a chain of free sources, a Greek source, a label photo
when nobody has the product, and a log of barcodes nobody had. No paid
vendors. This note is what the decision in ADR-421 rests on.

## Summary

| Source | Barcode lookup | Nutrition | Greek coverage | Licence | Limits | Used |
|---|---|---|---|---|---|---|
| Palee's own store (`food_products` cache) | yes | per 100 g, as the source gave | whatever was scanned | per row, the source's | none (our DB) | yes, first |
| Open Food Facts | yes, `GET /api/v2/product/{code}.json` | per 100 g (and per serving) | best open source for Greece; crowd-sourced, uneven | ODbL 1.0 (database), DbCL (contents), CC BY-SA (images) | 15 product reads/min/IP, custom User-Agent | yes, 1st remote |
| USDA FoodData Central, Branded Foods | yes, by search on `gtinUpc` | per 100 g (+ label per serving) | US market; few Greek products (some exported brands) | CC0 1.0 (public domain); credit asked | 1,000 requests/hour/IP; DEMO_KEY 30/hour, 50/day | yes, 2nd remote, only with a key |
| posokanei.gov.gr (successor of e-katanalotis) | yes, in its app and site | no | ~8,000–10,000 product codes from 10 chains | not stated; no published API or dataset found | n/a | no (see below) |
| Verified by GS1 / GS1 Association Greece | yes | no (name, brand, net content, image) | all GS1 Greece (520/521) codes | GS1 terms of use | 30 single queries per 24 h free; API for members | no (not free at our volume) |
| data.gov.gr | no supermarket product dataset with barcodes found | — | — | open data (Ν. 4727/2020) | — | no |
| Greek product list we import (`food_catalogue_products`) | yes (local) | no | whatever list we obtain | the list's own, kept per row | none (our DB) | yes, 3rd, empty until a list is licensed |

Nothing Greek and free gives nutrition by barcode. The Greek sources that know
barcodes (the ministry's price observatory and GS1 Greece) give at most name,
brand and size, and neither publishes them for reuse today. So the Greek source
in Palee is an import adapter: a list we are allowed to use (barcode, name,
brand, size, its licence) is imported with `mix palee.food_catalogue.import`
and looked up locally. Until such a list exists the table is empty and the
source answers "not found" in under a millisecond. The label photo fills the
nutrition gap for the member, and the miss log tells us which products matter.

## Open Food Facts

* API: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=…`;
  no key; "always use a custom User-Agent to identify your app", format
  `AppName/Version (ContactEmail)`.
  Source: <https://openfoodfacts.github.io/openfoodfacts-server/api/>
* Rate limits (official, read 2026-11-03): **15 req/min/IP** for product reads,
  10 req/min/IP for search; abuse can end in an IP ban. ADR-376's adapter
  note said 100/min (an older figure); corrected in code. The 30-day cache and
  the outbox keep Palee below this; the chain asks OFF once per barcode per
  cache period.
* Licence: database ODbL 1.0, individual contents Database Contents License,
  images CC BY-SA (may contain third-party marks).
  Sources: <https://openfoodfacts.github.io/openfoodfacts-server/api/>,
  <https://wiki.openfoodfacts.org/ODBL_License>,
  <https://support.openfoodfacts.org/help/en-gb/12-api-data-reuse/94-are-there-conditions-to-use-the-api>
* Greek coverage: Greek pages exist (gr.openfoodfacts.org, ~2,900 brands listed
  on the Greek brands facet); the product count could not be read from here
  (the site answered "temporarily unavailable" to the search API and the wiki
  is behind bot protection). The miss log (below) will measure our real gap.

### ODbL share-alike and our cache

* `food_products` holds extracts of OFF rows taken **unmodified** (name, brand,
  quantity, serving, image URL, categories, six nutrients per 100 g) plus our
  own computed `portion_hint`. Rows from other sources sit next to them, each
  row from exactly one source (`source` column), never merged.
* Under ODbL §4.4 (share-alike) a *Derivative Database* that is **publicly
  used** must be offered under ODbL. Showing a product to a member is a
  *Produced Work* (§4.3): it needs the notice/attribution, which every
  answer carries (`attribution`: source, licence, link). Our cache is not
  published or handed to anyone, so share-alike is not triggered today.
* If we ever publish the cache, export it, or let another system use it
  (e.g. a public API, ADR-378), the OFF-derived rows (with our added
  `portion_hint`) must be offered under ODbL. Keeping one source per row
  and the `source` column makes that a filter, not a cleanup.
* Never mix OFF rows with members' own foods or label reads: those are
  personal data (vision §4.5) and would otherwise be pulled into the
  share-alike obligation. They stay in `custom_foods`, private to the member.
* Contributing back (OFF asks for it) needs the member's explicit choice to
  share. Since the ADR-421 addendum (2026-11-03) that choice exists
  («Μοιράσου το»): only when the member explicitly shares is the product
  (data only, no photos) sent, through OFF's write API with Palee's account.

## USDA FoodData Central (Branded Foods)

* API guide: <https://fdc.nal.usda.gov/api-guide/>. Key from api.data.gov
  (free sign-up), passed as `api_key`. `POST /fdc/v1/foods/search` with
  `{"query": "<gtin>", "dataType": ["Branded"]}`; branded items carry
  `gtinUpc`, `description`, `brandOwner`/`brandName`, `servingSize` +
  `servingSizeUnit`, `householdServingFullText` and `foodNutrients`
  (per 100 g; nutrient numbers 203 protein, 205 carbohydrate, 204 fat,
  291 fibre, 269 sugars, 307 sodium in mg → salt = sodium × 2.5).
  Palee matches `gtinUpc` exactly (leading zeros ignored, since FDC stores
  UPC-A as 12 digits and Palee normalises it to EAN-13).
* Rate limits: "a default rate of 1,000 requests per hour per IP address";
  over it, HTTP 429 and the key is blocked for an hour; DEMO_KEY 30/hour and
  50/day. Usage is in `X-RateLimit-Remaining`. Source: the API guide above,
  and <https://api.data.gov/docs/rate-limits>.
* Licence: "USDA FoodData Central data are in the public domain and they are
  not copyrighted", CC0 1.0; USDA asks to be credited. No share-alike.
* Coverage: US-labelled products (GDSN/Label Insight data from brand owners);
  useful for imported and US brands sold in Greece, rarely for Greek ones.
* In Palee: `USDA_FDC_API_KEY`; without it the source is skipped (sandbox, dev,
  and any deployment that did not sign up). Energy is never kept.

## Greek sources

### e-katanalotis → posokanei.gov.gr (Ministry of Development / digital governance)

* Ν. 4796/2021 and Ν. 5019/2023 oblige supermarket chains to report daily
  shelf prices to the observatory «e-katanalotis»; in June 2026 the service
  became posokanei.gov.gr (site and apps), searchable "by product title or
  barcode", ~8,000 products from 10 chains at launch (~10,000 codes planned).
  Sources: <https://en.protothema.gr/2026/06/17/how-posokanei-works-22-questions-answers-about-the-new-digital-platform-how-it-differs-from-e-katanalotis/>,
  <https://www.naftemporiki.gr/finance/154018/se-leitourgia-i-nea-psifiaki-platforma-e-katanalotis/>,
  <https://www.powergame.gr/ikonomia/628613/e-katanalotis-pano-apo-3-500-kodikoi-sti-nea-platforma/>
* What it gives: product name, size, chain prices; **no nutrition**.
* No public API, dataset or licence was found (searched the press, data.gov.gr
  and GitHub); `e-katanalotis.gov.gr` now redirects to posokanei.gov.gr, which
  answered 403 to our server. Calling its private app endpoints or scraping
  it would be reuse without a licence, so Palee does not.
* Legal route: public-sector information is reusable under Ν. 4727/2020
  (Open Data Directive 2019/1024). A reuse request to the ministry for the
  product list (barcode, name, brand, size; prices not needed) is the way to
  get a Greek list that `mix palee.food_catalogue.import` can load.
  The ministry's «Μόνιμη μείωση τιμής» lists also name products by barcode,
  brand and size (<https://www.forin.gr/articles/article/86968/upourgeio-anaptukshs-prwtoboulia-gia-meiwsh-timwn-se-1000-kwdikous-sta-rafia-twn-souper-market>),
  but are published as press PDFs, not data.

### GS1 Association Greece / Verified by GS1

* GS1 Greece issues the 520–521 prefixes; Verified by GS1 holds brand-owner
  data per GTIN: brand, label description, net content, image; no nutrition.
* Free use: "up to 30 single GTIN queries in any 24-hour period"; API and
  batch access through the member organisation (paid membership/contract).
  Sources: <https://support.gs1.org/support/solutions/articles/43000734075>,
  <https://support.gs1.org/support/solutions/articles/43000734077-what-is-verified-by-gs1->,
  <https://gs1.org/locations/greece>
* Not usable for a scan feature without a contract → excluded (no paid vendors).
  GS1 Greece's GDSN data pool (used by Greek dairies, e.g. the yoghurt case
  study) does carry nutrition, but only for subscribers.

### data.gov.gr

* No dataset of supermarket products with barcodes. Source checked:
  <https://data.gov.gr> (API documented by <https://pydatagovgr.readthedocs.io/>).

### Retailers

* No Greek chain publishes an open product API. Third-party scrapers of
  Skroutz and chains exist (e.g. on Apify) and would breach their terms;
  excluded.

## Label photo (when nobody has the product)

* Reuses the platform's Gemini vision call (ADR-157, `GeminiVision`, metered per
  ADR-152, `GEMINI_API_KEY`); only the two photos and a fixed instruction are
  sent, never who sent them. The photos are read in memory during the request
  and never stored (Plug deletes the upload's temp file when the request
  ends). Without a key the action is hidden.
* The model returns name, brand, portion and the six nutrients per 100 g and
  per portion; energy is not asked for. The member checks and edits the
  prefilled «Δικό μου τρόφιμο» before anything is saved; it stays private.

## Barcodes nobody had

* `food_barcode_misses`: barcode, country (ISO 3166 alpha-2 of the member's
  main «Η περιοχή μου», else empty), scan count, first and last day.
  No user, no time of day, no box. Shown to the Palee team in the platform
  console («Barcode χωρίς προϊόν»), most scanned first.

## Open questions for the product owner

1. Ask the Ministry of Development for a reuse licence of the posokanei product
   list (barcode, name, brand, size) under Ν. 4727/2020? It is the only Greek
   list that could feed the Greek source for free.
2. Should a member be able to share a label-read food with every Palee member
   (and with Open Food Facts)? Needs a new explicit choice in the form and a
   privacy note; until then label reads stay private. **Answered**
   2026-11-03: yes, by an explicit, never pre-ticked choice (ADR-421 addendum).
3. Sign up for a USDA FoodData Central key (free) for production?
