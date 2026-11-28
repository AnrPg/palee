# ADR-797: «Εκκαθάριση συναλλαγών» with filters and a details side panel
Date: 2026-11-28
Status: Accepted

## Context
The cleanup dialog (Finance → Λογιστικά and Settings → Οικονομικά, the
password-confirmed soft delete «Εκκαθάριση οικονομικών εγγραφών»)
only searched by document number or id, showed at most 50 rows, and each row
showed the code, the amount and raw English words (`payment`, `paid`). Staff
could not see who paid or for which package, so finding the wrong record meant
guessing. ANR asked (2026-11-28) for filters by customer/account name, date and
package, and for a side panel with more information when a transaction is
clicked. ANR picked from the mockups
(`/mnt/project-files/milos/finance-cleanup/finance-cleanup-mockups-2026-11-28.html`):
1A search + «Φίλτρα», 2A side panel, and all small decisions α–θ.

## Decision
- **One search field** matches the customer's name, @handle or email and the
  document number or record id (β).
- **«Φίλτρα»** (the shared `CollapsibleFilterBar`) holds: Πελάτης (person
  picker), Από / Έως (inclusive, issue date of a document or paid date of a
  payment) with quick chips Σήμερα / Αυτός ο μήνας / Προηγούμενος μήνας / Φέτος
  on the gym's clock, Πακέτο συνδρομής (inactive packages included, marked) and
  Είδος (Τιμολόγιο, Απόδειξη, Πληρωμή). Nothing is preset: without filters the
  newest records show (γ, δ, ε).
- **Rows** show customer, amount, kind, status in words, package and date (α).
- **Pages**: keyset pages of 30, newest first, «Περισσότερες» at the end (ζ).
  The cursor is the opaque `{inserted_at, id}` of the last row, so pages never
  repeat or skip a record while records are added or purged.
- **Side panel** (drawer over the dialog, full screen on phones): customer with
  email and «Άνοιγμα μέλους» (ledger `?tab=members&member=`), facts (number,
  status, package, issue/due/paid dates, period, method, balance, refunded,
  recorded by, tax reference, note), invoice lines with totals, linked records
  (a receipt's payments, a payment's document) that open in the same panel (η).
  The cleanup sits last, closed until «Εκκαθάριση…»; after it the panel closes,
  the list refreshes and «Η εγγραφή εκκαθαρίστηκε.» shows (θ).

## Rationale
- The search and filter pattern is the console's own (2026-10-22 rule), so no
  new interaction to learn; the drawer keeps the list wide and the dangerous
  action out of the way until asked for.
- Hexagonal split: the filter, cursor and page merge are pure
  (`Finance.Domain.CleanupRecordFilter`); the SQL lives in its own adapter
  (`Infrastructure.Finance.EctoCleanupRecordStore`, out of the 7k-line finance
  store) behind `FinanceStore` callbacks; the application layer
  (`Application.ListFinanceCleanupRecords`) joins Finance and Identity: the free
  text is matched against the business's own customers (everyone who ever had a
  membership, never the whole platform) and records get names and emails there.
- Every query is tenant scoped in the adapter as well as by row-level security.

## Alternatives Considered
- Always-visible filter pills (1B): busier on phones, unlike the other lists.
- Two columns or inline expansion (2B, 2C): narrow columns or a jumping list.
- Offset pages: skip or repeat rows when a record is purged between pages.
- Joining the `users` table from the finance adapter: crosses a context
  boundary and `users` has no RLS.

## Consequences
- API: `GET /admin/finance/cleanup-records` takes `q`, `user_id`, `package_id`,
  `from`, `to`, `kind`, `cursor`, `limit` (≤ 100) and returns
  `{records, next_cursor}`; new `GET /admin/finance/cleanup-records/:id?record_type=`
  and `GET /admin/finance/cleanup-records/packages`, all `manage_billing`.
  Records lost the English `label` and the «… / payment xxxx» code; `code` is
  now the document number only.
- Old `Ui.featureFinanceCleanup*` messages moved to the `FinanceCleanup`
  namespace in all 12 languages.
- The customer picker lists current members and athletes; a former customer is
  still found through the search field.

## Implementation Notes
- A receipt's «recorded by» comes from its payment's `params.created_by_id`
  when the document has none (paid documents store it on the payment).
- Balance due reuses `Finance.invoice_balance_due_map/2` (credits and reversals
  included) instead of a second formula.
