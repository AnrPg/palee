# ADR-350: Consent per channel and purpose, STOP, and message wording per language
Date: 2026-10-31
Status: Accepted

## Context
GDPR and the ePrivacy rules (Greek law 3471/2006, art. 11) require prior consent for
marketing by SMS; WhatsApp requires opt-in for any business-initiated message; Palee's
principles keep marketing opt-in (plan, "GDPR"). Messages should arrive in the person's
language.

## Decision
1. **Contacts** (`channel_contacts`): a member (`user_id`) or a lead (`lead_id`, CP-C1) with
   a mobile in E.164 and a language (12 locales). One per person per box.
2. **Consents** (`channel_consents`): per contact, channel and purpose — `service`
   («Ενημερώσεις»: the person's bookings, classes, payments) and `marketing` («Προσφορές»).
   Each keeps `granted_at`, `withdrawn_at`, `source` (`person`, `staff`, `form`, `import`,
   `stop_keyword`), `text_version` and who recorded it. Nothing is assumed: a membership
   contract or a lead form's general consent does not grant SMS consent; marketing never
   stands in for service or the reverse. The member manages theirs at
   `GET/PUT /api/org/:slug/me/channels`; staff record what the person told them.
3. **STOP**: an inbound reply that is only a stop word (STOP, ΣΤΟΠ, ΔΙΑΚΟΠΗ, ΑΠΕΓΓΡΑΦΗ,
   UNSUBSCRIBE…; case and accents ignored) — or Brevo's own `unsubscribed` event —
   withdraws every consent of every contact with that number in the box and sets
   `opted_out_at`. Only a new consent from the person clears it. Inbound texts are not
   stored. Marketing SMS end with «Για διακοπή απάντησε STOP.» (in the message's language).
4. **Wording**: each message names a template key. Palee writes `class_cancelled`,
   `class_changed`, `booking_reminder`, `waitlist_spot`, `payment_due`,
   `package_expiring`, `trial_reminder` (service), `lead_follow_up`, `win_back`
   (marketing) and `box_message` (free text) in Greek and English; the box may rewrite any
   key per language (`channel_templates`, channel `any`). The person's language is used,
   then English. A missing placeholder is an error, never an empty gap. WhatsApp rows carry
   the provider's template id and Meta's approval status; WhatsApp only sends approved
   templates.

## Rationale
Consent per channel and purpose is the narrowest reading of the rules and matches what the
consent screen can show plainly. Keeping the consent ledger on the contact keeps
`consented?/4` one query.

## Alternatives Considered
- One consent for "messages" (all channels): fails WhatsApp's opt-in rule and GDPR's
  specificity.
- START keyword to opt back in: left out; open question for ANR.

## Consequences
- Events of a box or an organiser (product owner, 2026-11-02): «Θα έρθω» may carry
  `sms_consent` and `phone`; they are recorded first (a wrong number changes nothing) as a
  `service` SMS consent with the event's organisation, source `person`, text `event_rsvp_v1`
  (`Application.EventSms`). The reminder and a change then also go by SMS (`event_reminder`,
  `event_changed`) on top of push; without consent or a connection, only push goes.
- Leads: W2's lead form records contact and marketing consent, not SMS consent, so leads get
  no SMS until the form asks per channel or the integrator maps it (open question).
  `ChannelContacts.record/2` takes number and consents from a form or import.
- An alphanumeric sender cannot receive STOP replies: a numeric sender, or Brevo's
  unsubscribe handling, is needed for reply-based STOP (open question).

## Implementation Notes
`Channels.consented?(context, %{user_id: id} | %{lead_id: id}, channel, purpose)` is the
public check other contexts use (W10 keeps its own email marketing consent).
