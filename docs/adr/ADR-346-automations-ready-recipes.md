# ADR-346: Automations from ready recipes, quiet hours, opt-out and a narrow channel port
Date: 2026-10-31
Status: Accepted (CP-C2; builds on ADR-112, ADR-144, ADR-199, ADR-267)

## Context
Competitors offer automation builders (PushPress, Wodify, Glofox,
Mindbody). Our users are small boxes that need a few dependable messages,
not a workflow designer. The product owner decided SMS goes through Brevo
(W3 builds that adapter) and Viber is out.

## Decision
- Six **recipes**, each off by default, switched on per box
  («Αυτοματισμοί»): `welcome` (box member joined), `trial_follow_up` (trial
  class attended or a lead moved to trial), `missed_classes` (no visit for
  N days, default 10), `renewal_reminder` (package ends in N days, default
  5), `birthday` (the member shares day and month), `win_back` (a member
  became high risk, ADR-347).
- A box may change the channels (ordered), the delay, the subject and text
  (placeholders `{first_name}`, `{box}`, `{days}`, `{package}`, `{ends_on}`)
  and a few bounded settings; defaults exist in all 12 locales.
- **Triggers**: domain events (`membership_activated`,
  `attendance_recorded`, `lead_moved`, `member_at_risk`) and a daily scan
  after the box's send hour. Every planned message has a `trigger_ref`
  that is unique per box and recipe, so replays never send twice.
- **Outbox** (`automation_deliveries`): claimed with `FOR UPDATE SKIP
  LOCKED`; at send time the policy re-checks recipe on, recipient still
  in the box, opt-outs and consent; quiet hours 21:00–09:00 in the box's
  time zone defer to the next allowed time (DST safe); transient channel
  errors retry with backoff, at most 5 times.
- **Consent**: marketing recipes (`birthday`, `win_back`) need marketing
  consent for leads; box members may opt out of everything or per recipe
  in «Αυτόματα μηνύματα» and from the email footer.
- **Channel port** `Palee.Automations.Ports.Channel` (`reachable?/1`,
  `deliver/1` → `{:ok, ref} | {:error, {:transient | :permanent, r}}`):
  `in_app` (bell + push, notification type `box_automation`, category
  «Μηνύματα») and `email` (outbox, transactional, max 3 per day). W3's
  Brevo SMS adapter registers as `sms` in `config :automation_channels`.
- Capability `manage_automations` (owner, admin; box-wide).

## Rationale
Ready recipes cover the messages boxes actually send, with safe defaults
and no way to build a spam loop. A narrow port lets new channels plug in
without touching recipes.

## Alternatives Considered
- A general workflow builder (triggers, branches, waits): out of scope by
  the plan and against the calm-default principle.
- Sending immediately from event handlers: no quiet hours, no retries, no
  idempotency. Rejected for the outbox.

## Consequences
- `trial_follow_up` and `renewal_reminder` overlap ADR-144 and ADR-112
  notices; they default to email only so a member does not get two bells.
- Palee does not collect dates of birth (ADR-267); birthdays are an opt-in
  day and month in `automation_member_preferences`.

## Implementation Notes
- Migrations `20270502100000_create_automations`,
  `20270502300000_add_box_automation_notification_type`.
- Workers: `DispatchAutomationsJob` every 5 minutes, `DailyAutomationsJob`
  hourly (also purges stale leads).
- Endpoints `/api/org/:slug/admin/automations` (index, messages, PATCH
  recipe, preview) and `/api/org/:slug/me/automatic-messages` (GET/PUT).
