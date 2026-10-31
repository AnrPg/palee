# ADR-344: Leads («Ενδιαφερόμενοι»): one pipeline per box, owner, tasks and conversion that keeps the history
Date: 2026-10-31
Status: Accepted (CP-C1; builds on ADR-142, ADR-222, ADR-267)

## Context
Boxes keep people who asked about the box but are not box members yet in
notebooks, Messenger and spreadsheets. Competitors (PushPress Grow, Wodify
Grow, Glofox Leads, Mindbody/ClubReady) sell a lead pipeline as the first
step of their growth suites. Palee had join links and a public box page
(ADR-142) but nothing that remembered an enquiry, who should call back, or
which enquiries became box members.

## Decision
A new bounded context `Palee.Leads` (ports in the domain, Ecto adapters,
one application service per controller):

- **Lead** (`leads`): name, email and/or phone (at least one), source, stage,
  owner (a staff member), interests, campaign, consent, `user_id` once the
  person has a Palee profile, `converted_at`, `lost_reason`.
- **Stages**: `new` («Νέος») → `trial` («Δοκιμή») → `offer` («Προσφορά») →
  `converted` («Έγινε μέλος») | `lost` («Χάθηκε», with a reason from a
  fixed list). Only conversion reaches `converted`; a converted lead does
  not move again. One open lead per email per box (partial unique index).
- **Sources**: `website_form`, `form`, `join_link`, `manual`, `csv`,
  `walk_in`, `referral`, `event`, `around_me`, `trial`,
  `prospect_assistant`. External sources carry an idempotent `source_ref`.
- **History** (`lead_events`): created, enquired_again, stage_changed,
  owner_changed, note, contacted, task_added, task_done, message_sent,
  converted, marketing_opted_out, details_changed. Kept after conversion.
- **Tasks** (`lead_tasks`): title, due time, assignee; the staff list
  «Επόμενες ενέργειες» shows open ones across leads.
- **Conversion**: automatic when `:membership_activated` names the lead's
  profile or email; manual from the lead (the person must already be a
  box member). A first attended class with a trial request moves a `new`
  lead to `trial`.
- **CSV import** with Greek and English headers, dry run first, at most
  2,000 rows; repeated imports update rather than duplicate.
- Capabilities: `manage_leads` (owner, admin, front desk).
- Integration ports for other workstreams: `BoxSiteIntake.submit/2` (W4 box
  site forms) and `ProspectLeadSink.capture/2` (W8), both idempotent on the
  submission id.

## Rationale
A fixed, short pipeline matches how a box works (enquiry, trial, offer) and
keeps reports comparable across boxes; free-form stages are a CRM feature
our users never asked for. Keeping events after conversion lets the box see
which source and which follow-up brought each box member.

## Alternatives Considered
- Custom stages per box: more flexible, but breaks reporting, automations
  and the calm-default principle. Rejected for now (open question).
- Leads as rows in `organization_memberships` with a `prospect` status: mixes
  people who never agreed to anything with box members and their rights.
  Rejected.
- External CRM sync only (HubSpot): boxes do not run one. Rejected.

## Consequences
- Seven new tenant tables across ADR-344/346/347 with forced RLS, the
  tenant-context trigger, audit and tenant data policies.
- Leads are in the GDPR export of the person (by `user_id`) and the box's
  tenant export; account deletion removes the person's leads.
- Branch (location) scoping of leads is not done yet: leads are box-wide.

## Implementation Notes
- Migration `20270502000000_create_leads`.
- Endpoints under `/api/org/:slug/admin/leads` (list with stage counts,
  create, show, update, move, notes, contacted, tasks, convert, opt-out,
  import, delete).
- `Palee.Leads.Domain.Pipeline` holds the stage rules as pure functions.
