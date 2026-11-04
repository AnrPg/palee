# ADR-452: myDATA lost answers, batched sends, claim heartbeat and problem notices
Date: 2026-11-04
Status: Accepted

## Context
An audit of the ADR-243 myDATA reporting (ANR asked "is it functional, robust and tested?",
`/mnt/project-files/milos/mydata-audit-2026-11-04.md`) found these gaps:

- **Κ1:** if AADE registered a document but its answer was lost (timeout, 5xx, a dead
  worker), the retry sent it again. AADE answers "already sent", and that was stored as a
  rejection with no MARK.
- **Κ2:** a worker claimed 25 rows and sent them one by one, each with a 30 s timeout. That
  is up to 12.5 minutes, longer than the 10 minute claim timeout, so a second worker could
  take over rows that were still in flight.
- **Κ3:** nothing had ever talked to AADE itself. Every test used a stub.
- **Κ4:** nobody heard about refused or failed documents. Only a broken connection sent a
  notice.
- **Κ5:** the cron job swept every box inside a single job.
- **Κ6:** each document went in its own HTTP call.

## Decision
1. **Batches (Κ6, Κ2).** The claimed rows of a box go to AADE in one `InvoicesDoc`.
   `AuthorityGateway.submit/2` takes a list of invoices and returns one result per
   invoice, matched by AADE's 1-based `index`. An invoice with no answer is transient.
   The wire map carries `request_bodies`, so each attempt row keeps only its own document.
2. **Claim heartbeat (Κ2).** Before every call to the authority (a send or a look-up), the
   claims of the batch are renewed (`TransmissionStore.touch_claims/3`). A test guards that
   the longest single call is shorter than the claim timeout. That call is one send
   (`receive_timeout`) or one look-up through all its pages (`check_timeout ×
   max_lookup_pages`).
3. **Lost answers (Κ1).**
   - A row that may already be at AADE is first looked up with
     `AuthorityGateway.find/2`. For myDATA that is `GET /RequestTransmittedDocs` for the
     issue day and type, following the continuation token, and matching issuer ΑΦΜ,
     series, number, date and type. If AADE has the document, its MARK is taken and the
     row is accepted. Otherwise the document is sent. "May already be at AADE" means its
     last attempt ended `transient`, or an earlier claim never finished (a worker died
     mid-call, the claim expired and the row was claimed again: `attempts` > 1, since
     deferrals do not count as attempts).
   - If AADE answers "already sent" (`MyDataGateway.duplicate_codes/0`, today `233`, the
     code the v1.0.12 documentation lists for providers), the result is
     `{:duplicate, errors}`, which triggers the same look-up. When nothing is found, the
     rejection stands.
   - When several listed entries match (a resend registered again), `find/2` takes the
     first registration, the lowest MARK, and skips cancelled ones.
4. **Notices (Κ4).**
   - New notification type `fiscal_documents_not_reported` (migration `20270706000000`),
     built by `ConnectionNotifier.documents_not_reported/3`. It goes to the people with
     `manage_billing`, at most once a day per connection and person, and links to
     Finance › Documents.
   - The staff home «Θέλει προσοχή» shows «N παραστατικά δεν έφτασαν στην ΑΑΔΕ», from the
     `counts` of `GET /admin/fiscal/transmissions` (rejected + failed).
5. **Per-box runs (Κ5).** The cron job only fans out. It calls `FiscalReporting.schedule/1`
   for each active box: a job of its own in production, and an inline run when background
   jobs are off.
6. **Live sandbox test (Κ3).** `test/palee/infrastructure/fiscal/my_data_live_test.exs`
   (`@tag :aade_live`) runs against `mydataapidev.aade.gr` and checks:
   - «Δοκιμή σύνδεσης» with the right key and with a wrong one;
   - a batch of two receipts;
   - a resend, which may come back as a duplicate or with a new MARK;
   - `find/2`, both found and not found. It retries while AADE indexes the new documents
     and while the dev API answers 429.

   It runs only on request, `mix test --only aade_live`, with `MYDATA_DEV_USER`,
   `MYDATA_DEV_KEY` and `MYDATA_DEV_VAT` set. Normal runs exclude it, because the dev API
   is slow and rate-limited.

## Rationale
- Looking the document up before a resend prevents the duplicate. The live run showed that
  AADE's development API does not refuse a resend at all: it registers the same UID again
  under a new MARK. So the look-up, not the "already sent" answer, is what stops a second
  registration, and it also covers a worker that died after AADE answered. Handling
  "already sent" stays as a second line in case production enforces it.
- Matching on the document's own keys avoids recomputing AADE's UID hash, whose exact
  input order we would otherwise have to copy.
- A heartbeat bounds every claim by one call, whatever the batch size.

## Alternatives Considered
- **One row per claim.** This also fixes Κ2, but it costs one HTTP call per document and
  does nothing about Κ1.
- **A longer claim timeout alone.** It is fragile: it breaks again as soon as the timeouts
  or the batch size change.
- **Computing the UID and calling `RequestTransmittedDocs` by MARK range.** This needs
  AADE's exact UID formula.

## Consequences
- A recovered document has the MARK, UID and `qr_url` (`qrCodeUrl`) that AADE lists.

## Live run (2026-11-04)
The live test ran against `mydataapidev.aade.gr` with AADE test keys:
- «Δοκιμή σύνδεσης» works; a wrong key is 401.
- Retail receipts (11.x) were refused with error 204 "Currency is mandatory for this invoice
  type", although the XSD marks `currency` optional. `MyDataInvoice` now always sends
  `<currency>` (EUR included).
- A resend of the same document is accepted with the same UID and a new MARK; the
  development API never answered "already sent". The look-up before a possible resend
  (above) now covers the dead-worker case too. Whether production answers `233` is still
  unknown.
- `RequestTransmittedDocs` with `mark=0`, `dateFrom`/`dateTo` (dd/MM/yyyy) and `invType`
  works and filters (another type or day lists nothing); `find/2` returns the first MARK.
- A few calls in a row get HTTP 429 with `Retry-After` of about 30 s. In the outbox this is
  transient, and the first backoff (60 s) is longer. The live test waits it out.
- AADE's own v1.0.12 XSDs (sent by ANR) are kept in `priv/fiscal/mydata/v1.0.12`. Every
  generated document is validated against both them and `v2.0.1`. `v2.0.1` (from npm) is a
  superset of v1.0.12 except `otherTransportDetails`, which we do not use.

## Implementation Notes
- `SandboxAuthorityGateway.find/2` always answers `:not_found`, because the sandbox keeps
  nothing.
- `TransmissionPolicy` treats an unresolved `{:duplicate, _}` as a rejection.
