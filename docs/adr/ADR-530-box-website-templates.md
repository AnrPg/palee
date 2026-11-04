# ADR-530: Box website templates, palettes and publishing
Date: 2026-11-04
Status: Accepted (extends ADR-352, ADR-388, ADR-520)

## Context
The box website (ADR-352/388) was one page that stacked the owner's sections
in the owner's order, in the app's look. ANR asked for four preset templates
with pages, widgets, animation and gestures, and 12 predefined colour
palettes. Everything is filled and kept in sync from Palee data. Mockup:
https://claude.ai/artifact/JhRJ8ZwAiHzBaj8jSzof16 (round 2). ANR's answers
(2026-11-04, 01:45–02:30 UTC):
- Every section we support works in all four templates as an on/off switch.
  Order no longer applies, because each template has its own flow. Each
  template must look good with any subset of sections.
- More motion everywhere, unless the box turns on «Λιγότερη κίνηση».
- Pages are SEO and GEO optimised, and the settings say so.
- Palettes apply to the website only; the Palee app keeps its one theme.
- The box picks one of «Αυτόματα», «Πάντα φωτεινή» or «Πάντα σκοτεινή».
- «Αριθμοί κοινότητας» shows aggregates only and can be switched off.
- For new boxes the timetable is on by default and the WOD is off.
- Template, colours, motion and section switches go live only with
  «Δημοσίευση»; until then they are a draft the owner can preview.
- Existing sites move to template «Αρένα» with the Palee palette, and the
  box gets a notice.

## Decision
1. **Settings.** `box_site_settings` gets these new columns:
   - `template`: `arena | tiles | stories | atelier`. New rows default to
     `tiles`; the migration sets existing rows to `arena`.
   - `palette`: one of 12 keys (`palee electric flame sun amber emerald
     aegean violet fuchsia olive navy mono`, default `palee`).
   - `appearance`: `auto | light | dark`, default `auto`.
   - `calm_motion`: boolean, default false.
   - `draft`: jsonb, null when nothing is waiting.
   - `published_at`.
   - `template_notice`: true for sites the migration moved, until the owner
     publishes or dismisses the notice.

   The backend validates keys only. Colours are presentation and live in the
   web (`components/box-site/templates/palettes.ts`).
2. **Draft and publish.** The publishable fields are `template`, `palette`,
   `appearance`, `calm_motion`, `hidden_sections`, `public_schedule` and
   `public_wod`.
   - `PUT /admin/site` merges these fields into `draft`. Every other field
     (FAQ, languages, tags, forms) saves at once, as before.
   - `POST /admin/site/publish` applies the draft and clears it.
   - `DELETE /admin/site/draft` throws the draft away.
   - `GET /admin/site/preview?lang=` answers the public-site shape with the
     draft applied. The settings page renders it with the same components
     visitors get.

   `section_order` stays stored but the templates ignore it.
3. **Sections.** New keys:
   - `photos` («Φωτογραφίες»): the box page photos plus room photos marked
     🌐.
   - `stats` («Αριθμοί κοινότητας»): classes this week, PRs this year and
     years open. These are aggregates only, and a zero hides the number.
   - `programmes` («Προγράμματα»): the programmes the box sells (ADR-370,
     published and on sale), each linking to its public page. The section
     hides while there is none.

   As before, a switched-on section with no data is hidden.
4. **Rendering.** One engine, `components/box-site/templates/`, with four
   template components that share the widgets (timetable, map, reviews, FAQ,
   gallery, forms) and the page model:
   - The page model (`site-model.ts`) has pages Αρχική, Πρόγραμμα, Πακέτα,
     Coaches and Ο χώρος. A page with nothing on it leaves the menu.
   - The main button falls back from the trial form to the contact form to a
     phone call.
   - Palette tokens `--s-*` are computed from the palette, the mode and the
     template. Text that fails WCAG AA is darkened or lightened.
   - Motion animates transform and opacity only. Reveals happen only below
     the first screen. `prefers-reduced-motion` and `calm_motion` both turn
     it off.
   - Each page has its own URL, which helps search engines.
   - Signed-in members keep the app's box page in the Palee theme. Visitors
     and the box's own domain get the template.
5. **SEO and GEO.** Every page has its own title, description, canonical
   URL and hreflang. JSON-LD covers `ExerciseGym` (name, address, phone,
   hours, rating), `Offer` for packages, `Event`, `FAQPage` and
   `BreadcrumbList`. The site also gets a sitemap entry for every page and
   `llms.txt`.

## Consequences
- Old sites keep their content. Only the look changes, and the owner can
  switch template at any time.
- The order arrows leave the settings page.
- Template changes are reviewed in a preview before they go live.

## Implementation notes (API, 2026-11-04)
- Migration `20271101000000_box_site_templates` adds the columns, a check
  constraint on the keys and `template_notice_sent_at`. It moves every
  existing row to `arena` with `template_notice`. A box that published its
  public page but never saved website settings gets a row too (`arena`,
  notice, timetable off, as it was). New rows default to `tiles` with
  `public_schedule` on; a box with no row reads the same defaults.
- `SiteSettingsPolicy` validates the keys. Publishable edits are merged into
  `draft` (string keys), keeping only the values that differ from the live
  columns. A draft equal to the live site is stored as null. Hidden sections
  compare as a set. `POST /admin/site/publish` without a draft still stamps
  `published_at` and clears the notice.
- `GET /admin/site/preview` builds the public-site shape for the staff
  member's own organization with the draft applied. It works before the
  public page is published: the box is found by its organization, not by
  `PublicBox.resolve/1`.
- Sections `photos`, `stats` and `programmes` exist, and a section with no
  data hides, as before. `photos` lists the page cover and photos, then the
  public room photos, 12 at most. `stats` has classes over the next 7 days,
  the PRs recorded in the box this calendar year (`palee_box_pr_count`, a
  SECURITY DEFINER count of records and history rows with the box's
  provenance) and whole years since the organization was created.
  `programmes` lists up to 6 programmes on sale (`SiteProgrammes`).
- `photos.video` and `phone` are always null for now (TD-530).
- The notice: `template_notice` drives the banner. `BoxSiteJob`'s cron also
  sends one `site_template_changed` notification to staff with
  `manage_settings`. The box is claimed first, through
  `template_notice_sent_at`. Demo businesses are never listed.
