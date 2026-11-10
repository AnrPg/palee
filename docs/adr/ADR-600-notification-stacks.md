# ADR-600: Similar notifications stack in the bell

- Status: accepted (ANR, 2026-11-10)
- Refines: ADR-460 (delete and «Αναίρεση»), ADR-199 (categories), ADR-171 (native push)
- Mockups: `/mnt/project-files/milos/notification-stacking/notification-stacking-mockups-2026-11-10.html`

## Context

Every notification was its own card and its own push. A box with fifteen
classes still without a WOD got fifteen «Τμήμα χωρίς WOD» cards and fifteen
pushes. ANR: similar notifications must all still arrive, but take the room
of one, stacked, with «+14 ακόμη παρόμοιες». The same holds for every type.

The bell loads 20 rows a page, so grouping in the browser would only join
what one page happened to hold: a wrong «+N», a stack split across pages, a
stack's delete missing the rows not loaded, and no way to collapse pushes.

## Decision

ANR's picks: A (a deck of cards), grouping on the server, «similar» = same
type, box and day with the exceptions below, a stack from 3, the bell badge
counts every notification, trash and closed eye act on the whole stack with
«Αναίρεση», opening a stack marks nothing read, a tap on a closed stack opens
it, one push that updates itself, a new similar notification lifts a read
stack back to the top as new («1 νέα»), and the bell's tabs filter on the
server.

### Domain

`Notifications.Domain.NotificationGrouping` decides a notification's
`group_key`, by type:

| Rule | Types | Key |
| --- | --- | --- |
| `:day` (default) | every type not named below, including future ones | `type:o:<box or ->:d:<day>` |
| `{:conversation, field}` | chat, coaching, box, box inbox, person, request, buddy, partner, support reply, event message | `type:c:<conversation>` (else the day key) |
| `:personal_day` | follow requested / accepted, new follower | `type:p:d:<day>` |
| `{:subject_day, "scheduled_for"}` | workout changed / note / moved | the day key with the WOD's day |
| `:never` | password reset requested / completed | nil |

"Day" is the box's day (ADR-176), or the recipient's without a box.
`min_stack_size/0` is 3. `push_tag/1` turns a key into a 38-byte tag.

### Storage

`notifications.group_key` (text) with the partial index
`(user_id, group_key, inserted_at DESC, id DESC) WHERE deleted_at IS NULL AND
group_key IS NOT NULL`. `CreateNotification` writes the key for every
notification. Migration `20271112100000_notification_group_key` backfills the
rows written before it with the same keys in SQL (a test checks it matches
the app).

### Inbox

`GET /notifications?stacks=true` partitions the live inbox by `group_key`:
a group of 3 or more is one row, its newest notification with `stack: {key,
count, unread_count}`; a smaller group lists every notification. Rows sort
and page by that newest notification, so a stack that receives a new one
returns to the top. `group_key` lists one stack; `types` narrows to types.
The unread count stays one per notification.

`POST /notifications/read {filter}` marks a stack read,
`POST /notifications/delete {filter}` deletes it (now answering
`restorable_for_seconds`), and `POST /notifications/restore {filter}` undoes
the delete within the ADR-460 window.

### Push

`DispatchNotification` gives a stack's push the stack's tag and appends
«+N more similar» (a gettext plural, 12 locales) for the other unread ones.
The stored row is unchanged. Web push shows it with `tag` and `renotify:
false`; FCM sets the Android `tag`; APNs sets `apns-collapse-id` and
`thread-id`. The phone keeps one notification per stack.

### Web

The bell asks for `stacks=true`, and the tabs send `types`. A stack row is
the newest card over two sheets, «+N ακόμη παρόμοιες» and «N νέες»; a tap
opens it in place (`group_key`) with «Σύμπτυξη». Its trash and closed eye
act on the whole stack, with «Αναίρεση». Counts are ICU plurals in 12
catalogs (`NotificationActions.stack*`).

## Consequences

- No notification is merged or dropped; the key only changes how they read.
- A new type stacks by the default rule without any change.
- The gettext validator now also checks plural entries.
- A pair of similar notifications shows as two cards but shares one push tag.
