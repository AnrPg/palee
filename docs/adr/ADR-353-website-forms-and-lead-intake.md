# ADR-353: Website forms (trial request, contact) and the lead intake contract
Date: 2026-10-31
Status: Accepted

## Context
CP-C5: a form on the box's website should create a lead (CP-C1, built by
workstream W2 in parallel). The two sides are developed at the same time, so
W4 must compile and test alone.

## Decision
1. `POST /api/public/sites/:slug/forms/:kind` (`trial` | `contact`), no
   account, own rate-limit bucket (10/min per address). Fields: `name`,
   `email` and/or `phone`, `message` (required for contact), `preferred_time`,
   `class_type_id`, `locale`, `marketing_opt_in`, `privacy_ack` (must be true),
   `visitor_id`, `attribution` (UTM keys, referrer host, landing path),
   and two spam guards: a honeypot `website` field and `elapsed_ms` (a form
   filled in under 2 s). A guarded post answers 202 like a real one and stores
   nothing.
2. The submission is written to `box_site_submissions`, an outbox, and answered
   202. `DeliverSiteSubmissionsJob` claims due rows (`FOR UPDATE SKIP LOCKED`)
   and hands each to the port **`Palee.BoxSite.Ports.LeadIntake`**:

   ```elixir
   @callback submit(context :: %{organization_id: Ecto.UUID.t()}, intake :: map()) ::
               {:ok, %{lead_id: Ecto.UUID.t()}}
               | {:error, {:rejected, term()}}
               | {:error, {:transient, term()}}
   ```

   `intake`: `submission_id` (idempotency key: the same id twice must return
   the same lead), `kind`, `source: "website_form"`, `name`, `email`, `phone`,
   `message`, `preferred_time`, `class_type_id`, `locale`, `marketing_opt_in`,
   `submitted_at`, `attribution`. The adapter is chosen by
   `config :palee, :box_site_lead_intake`; W2 supplies the real one. Until
   then production uses `HeldLeadIntake` (always transient: rows wait, never
   lost) and dev/test use `SandboxLeadIntake`.
3. Retries back off from 1 min to 6 h; after 12 attempts or a rejection the
   row is `failed`.
4. **Data minimisation.** When delivered, the outbox row's personal fields
   (name, email, phone, message, preferred time) are cleared (`redacted_at`):
   the lead is now the record, under W2's retention. Failed rows are cleared
   after 30 days. The form asks only what a box needs to answer.
5. **Lawful basis.** Answering the request is pre-contractual (GDPR 6(1)(b));
   marketing follow-ups need the separate, unticked `marketing_opt_in`
   (ePrivacy art. 13), passed on to the lead.

## Rationale
An outbox decouples the public form from the leads context and from failures,
keeps the 202 fast and lets W2's adapter arrive later without losing a lead.

## Alternatives Considered
- Calling the leads context directly from the controller: couples W4 to W2
  and loses submissions when leads fail.
- CAPTCHA: a third party on every visitor; honeypot + time + rate limit first.

## Consequences
- W2 implements the behaviour and sets the config; idempotency on
  `submission_id` is their side's duty.
- Migration `20270504000000_box_site.exs`.
