# ADR-460: Deleting and hiding notifications
Date: 2026-11-04
Status: Accepted

## Context
The bell drawer only let a person open a notification or mark all read. The product owner (ANR)
asked for two actions on every notification card, and for a way to clear many at once from
«Εγώ › Ρυθμίσεις › Ειδοποιήσεις». A deleted notification must never come back in any client
(web, store apps, push badge), yet the GDPR export («Λήψη των δεδομένων μου») reports what the
backend holds.

## Decision
- **Card actions (option B of the mockup)**: trash (delete) then closed eye («Απόκρυψη» = mark
  read; it moves to the collapsed «Διαβασμένες»), inline SVG line icons in `currentColor`, translated
  aria-labels and a `HoverHint`. They take no layout space: with a fine pointer they overlay the
  card's top end corner on hover and on `:focus-within` (keyboard); on a coarse pointer they sit
  behind the card and a swipe to the left reveals them (swipe right, a tap on the card or a tap
  elsewhere closes; the swipe never acts by itself). Motion only under `prefers-reduced-motion:
  no-preference`. The buttons are siblings of the card, so they never open it. On a card already
  read the eye is `aria-disabled`.
- **Soft delete**: `notifications.deleted_at` (`utc_datetime_usec`, migration `20270710000000`)
  plus a partial index `notifications_live_inbox_index (user_id, inserted_at DESC, id DESC) WHERE
  deleted_at IS NULL` for the live list. Every read and mark path of `EctoNotificationStore`
  (`list_for_user`, `list_inbox_page`, `count_unread_inbox`, `count_inbox`, `mark_all_read`,
  `mark_read`, `get_notification_organization_id`, therefore click) goes through `live_inbox/1`
  or `not_deleted/1`. Realtime payloads carry only `user_id` and push carries no badge count, so
  nothing else reads the table. A `dedupe_key` stays taken by the deleted row: a retried job does
  not bring a deleted notification back.
- **Undo**: the delete is sent at once (robust to closing the tab) and the drawer shows «Η
  ειδοποίηση διαγράφηκε» / «Αναίρεση» for 6 s. `POST /notifications/:id/restore` clears
  `deleted_at` only while it is at most `NotificationFilter.restore_window_seconds/0` (60 s) old;
  after that it answers 410 `notification_not_restorable`. The client waits for its delete before
  sending the restore. Closing the drawer drops the toast.
- **Endpoints** (user-only scope, owner-only RLS, `scoped_to_user` like the rest of the store):
  `DELETE /notifications/:id` (idempotent; 404 for someone else's), `POST /notifications/:id/restore`,
  `POST /notifications/delete` with `{ids: [...]}` (at most 200) or `{filter: {state: all|read,
  older_than_days, category}}`, never both, answering `deleted_count`. `GET /notifications` takes the
  same filter as query params plus `include_count` (answers `matching_count`). Filters are parsed by
  the pure `Notifications.Domain.NotificationFilter`; a category maps to its ADR-199 types
  (`NotificationCategories.types_for/1`). Bulk deletes have no restore.
- **Settings card «Διαγραφή ειδοποιήσεων»** (`NotificationCleanup`): chips Όλες / Διαβασμένες /
  Παλαιότερες από 30 μέρες and a category row, a server-paged checkbox list (20 a page), «Επιλογή
  όλων (N)» sends the filter itself (N = `matching_count`), and the danger button «Διαγραφή N
  ειδοποιήσεων» asks in a `ui/Dialog` first. Copy in the `NotificationActions` namespace, 12 locales,
  counts as ICU plurals.

## Rationale
Sending the delete at once and restoring server-side survives a closed tab or a crashed app; a
client-deferred send would lose the delete. A short server window keeps «can never be retrieved»
true in practice. Sending the filter for "select all" deletes exactly what the list shows without
loading every id.

## Alternatives Considered
- Hard delete: breaks undo and the GDPR export's completeness.
- Client-deferred delete (send after the toast): lost when the drawer's tab closes.
- Always-visible buttons (option A): rejected by the product owner for the noise on every card.

## Consequences
- The GDPR export still lists deleted notifications (with `deleted_at`), since the backend keeps
  them; a retention job may purge old deleted rows later (not part of this change).
- The store apps must call the same endpoints; they read the same filtered lists already.

## Implementation Notes
- `DELETE /notifications/:id` is declared after `DELETE /notifications/push-subscriptions` so the
  literal route wins.
- Hidden inbox types (`chat_message`, `workout_completed`) can be neither listed nor deleted here.
