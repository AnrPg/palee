# ADR-541: A programme's cover photo, edited in the browser, original kept
Date: 2026-11-04
Status: Accepted

## Context
The programmes board (question 3) showed the cover as a colour strip from the
Palee theme and asked whether a coach may upload a photo of their own. ANR
approved: upload, then basic edits (crop to the cover's aspect, rotate by 90°,
zoom, brightness), and «Αφαίρεση» goes back to the strip.

## Decision
1. **The media pipeline, a new purpose.** `programme_cover` tenant media
   (ADR-148): public bucket (`media/public/programmes`), JPEG/WebP re-encoded in
   the browser and inspected before `ready`, 8 MB, like shop product photos.
   Staff with `manage_workouts` (who write programmes) upload them:
   `POST /admin/programme-covers` (presigned PUT) and
   `POST /admin/programme-covers/:id/complete`.
2. **The browser edits, the API keeps both.** The web edits on a canvas and
   uploads the rendered cover too. `PUT /admin/programmes/:id/cover` with
   `{media_id, original_media_id?, edit?}` stores the rendered cover
   (`cover_media_id`), the photo it came from (`cover_original_media_id`,
   default the same) and the edit (`cover_edit`: `rotation` 0/90/180/270,
   `zoom` 1–4, `brightness` 0.5–1.5, `crop` x/y/width/height in fractions of the
   original after rotation). Editing again starts from the original with the
   stored edit.
3. **16:9.** The rendered cover and the crop (in the original's pixels) must be
   within 2% of 16:9, at least 320×180 (`invalid_cover_size`); edit values out
   of range are `invalid_cover_edit`.
4. **Lifecycle.** The uploads are marked attached (the orphan sweep keeps
   them); replaced or removed ones are deleted unless another programme still
   shows them. `DELETE /admin/programmes/:id/cover` removes it.
5. **Shown everywhere as `cover_url`.** Staff payloads carry `cover_url` and
   `cover` (`media_id`, `url`, `original_media_id`, `original_url`, `edit`,
   `aspect`); public payloads (box page, one programme, the catalogue, the box
   website section) only `cover_url`. The catalogue projection
   (`palee_marketplace_programmes`, replaced; still SECURITY DEFINER pinning
   only `search_path`) returns the cover's object key of a ready cover and the
   application turns it into the public URL.

## Consequences
- Null `cover_url` means the theme strip, as in the mockups.
- No server-side image processing is added; the browser's render is what
  visitors see.
