# ADR-363: In-app support: an AI first line from help articles, hand-off to the Palee team
Date: 2026-10-31
Status: Accepted

## Context
CP-G3: staff ask Palee for help by email today, with no context. Most questions are answered by an
article. The Palee team needs a queue with the context to answer the rest.

## Decision
1. **Conversation** `help_desk_conversations` + `help_desk_messages` (tenant, forced RLS): a staff
   member's own conversation (others in the box cannot read it), with the screen path and locale.
   Statuses: `assistant`, `waiting_for_palee`, `answered_by_palee`, `resolved`.
2. **AI first line** (`HelpDesk.Assistant`, prompt `hd-1`): retrieves up to 4 articles for the
   question and screen (ADR-362), sends them as documents with the last 6 turns, and asks for
   `answer`, `citations` (slugs), `guide_id`, `confident`. Citations outside the given articles are
   dropped; a guide is offered only from a cited article. The assistant never sees the box's data and
   has no tools. Every reply says what happened: `answered`, `not_confident`, `no_articles`,
   `limit_reached`, `unavailable` or `skipped` (the team has it); the hand-off is always offered.
3. **Hand-off** creates `help_desk_tickets` (tenant + vendor policy): summary, the person's note,
   priority (`normal`/`urgent`), screen, articles tried, and app facts from a whitelist (version,
   platform, browser, screen size, time zone). Messages after a hand-off go to the team (the ticket
   reopens).
4. **Vendor queue**: `GET /platform/help-desk/tickets` (urgent first, then oldest), `GET …/{id}`,
   `POST …/{id}/replies` (`waiting_on_box` or `solved`), `PATCH …/{id}` (status, priority, assignee).
   Every read and write is in the vendors' audit log (ADR-273).
5. Staff API: `/admin/help-desk/conversations` (list, start), `/{id}` (show), `/{id}/messages`,
   `/{id}/hand-off`, `/{id}/resolve`. Limits per ADR-360 (feature `help_desk`).
6. In the GDPR export (the requester's messages and tickets) and purged with the box.

## Rationale
Answers from articles only, with citations, keep the assistant honest and checkable; the same
articles serve people who never open support. Keeping support per person avoids exposing what a
colleague asked.

## Alternatives Considered
- A third-party chat widget: data leaves Palee with no screen context; no 12-language articles.
- The assistant answering from general knowledge: wrong answers about Palee features.

## Consequences
- Notifications to the Palee team (email/push) on new tickets are not built: telemetry
  `[:palee, :help_desk, :ticket_opened]` is emitted for them.
- Members (not staff) do not have support yet; they have the help centre.

## Implementation Notes
- `lib/palee/help_desk/**`, `lib/palee/application/help_desk/**`,
  migration `20270506200000_create_help_desk.exs`.
- Messages written in the same instant are ordered question first.
