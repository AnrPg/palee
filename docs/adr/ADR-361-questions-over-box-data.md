# ADR-361: Questions over a box's data: a catalogue of typed read queries, no SQL, no names
Date: 2026-10-31
Status: Accepted

## Context
CP-F4: staff want to ask «Ποιοι δεν ήρθαν 3 εβδομάδες;» or «Έσοδα ανά πακέτο τον προηγούμενο μήνα»
without building reports. Text-to-SQL is fragile and unsafe under multi-tenancy; a model must also not
receive members' personal data it does not need (GDPR data minimisation).

## Decision
1. **Catalogue** `Palee.DataQuestions.Domain.Catalogue`: six versioned, typed read queries —
   `members_absent` (days 7..365), `member_counts` (period), `expiring_subscriptions` (days 1..90),
   `revenue_by_package` (period), `revenue_by_month` (months 1..24), `attendance_by_class_type`
   (period). Each declares its arguments (JSON Schema, unknown arguments refused), the capabilities it
   needs (with scope `all`) and whether it lists people. The model only sees the queries the asker may
   run; rights are checked again on every call.
2. **Reader** port `BoxDataReader`, adapter `SqlBoxDataReader`: parameterised SQL, run in the box's
   RLS session, with the organisation predicate written again in every query, rows capped at 100.
3. **The model never sees names**: results go to the model as `ResultShape.for_model/2` — people as
   opaque refs (P1, P2…), money in units, at most 20 rows, totals. Tables with names are built on the
   server from the same rows and returned only to the screen.
4. **Answers** follow a schema (`answer`, `citations`, `confident`); each cites query refs (`[q1]`).
   `Grounding` checks that every number in the answer is in the cited results (`grounded`). An answer
   without citations or not confident is stored as `not_answered`. Follow-up actions are suggestions
   (e.g. «Στείλε μήνυμα σε 2 άτομα», only when the asker may message clients) and never run alone.
5. **Switch and limits**: `organization_ai_settings.data_questions_enabled` (default **off**); limits
   per ADR-360 (feature `data_questions`).
6. **Audit**: `data_questions` (tenant, forced RLS): question, status, answer, citations (aggregates
   only), queries and steps run, prompt version, model, tokens, cost, duration. Never rows or names.
   Owners/admins with settings rights list everyone's; others their own. In the GDPR export and
   purged with the box.
7. API: `GET /admin/data-questions/catalogue`, `POST /admin/data-questions`, `GET /admin/data-questions`,
   `GET /admin/data-questions/{id}` (rate limited 20/min).

## Rationale
A catalogue is the ADR-300 operation registry in small: typed, permission-checked operations that a
model can call; v4 replaces the catalogue with registry read operations without changing the screen.

## Alternatives Considered
- Text-to-SQL with a read-only role: injection and cross-tenant risk, unreviewable queries.
- Sending rows with names to the model: needless personal data to a processor.
- Fixed reports only: exist (Analytics); questions fill the gaps between them.

## Consequences
- New questions need a new catalogue entry (code + test). Gaps are visible in `not_answered` logs.
- Gemini becomes a processor of aggregates only; the sub-processor list already names Google.

## Implementation Notes
- `lib/palee/data_questions/**`, `lib/palee/application/data_questions/data_questions.ex`,
  migration `20270506100000_create_data_questions.exs`.
- Revenue counts only payments of the membership and package revenue streams.
