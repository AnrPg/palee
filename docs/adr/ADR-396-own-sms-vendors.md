# ADR-396: A box's own SMS vendor: Twilio, Vonage, Infobip, Yuboto and Apifon besides Brevo
Date: 2026-11-03
Status: Accepted

## Context
v3.1 sends a box's SMS through Palee's Brevo account by default, with the box's own Brevo key as
the advanced option under «Προχωρημένα» (ADR-348/349/368/369/390). The product owner (ANR) agreed
on 2026-11-01 that boxes, solo coaches and event organisers may bring their **own SMS vendor**:
many already pay one (a Greek reseller such as Yuboto or Apifon, or Twilio/Vonage/Infobip abroad)
and want their messages, prices and sender names to stay there. ANR ruled out a generic HTTP
adapter: one adapter per popular vendor, each behind the existing port.

## Decision
1. **Five more adapters behind `Channels.Ports.MessagingChannel`**, SMS only, own account only
   (`account_modes: ["own"]`; Palee's account stays Brevo): `TwilioChannel`, `VonageChannel`,
   `InfobipChannel`, `YubotoChannel`, `ApifonChannel` (`config :palee, :channel_providers`). HTTP
   goes through `Infrastructure.Channels.Http` (Req, `req_options` from config, `Req.Test` plugs in
   tests, never retrying by itself).
2. **Each vendor's fields** (`Channels.Domain.VendorRules`, pure):

   | Vendor | `account_id` | `secret` | `base_url` | `webhook_secret` |
   |---|---|---|---|---|
   | Brevo | – | API key | – | – |
   | Twilio | Account SID (`AC` + 32 hex) | Auth Token | – | – |
   | Vonage | API key | API secret | – | signature secret (optional) |
   | Infobip | – | API key | `https://<id>.api.infobip.com` only | – |
   | Yuboto | – | OMNI API key (Base64 as Octapush shows it; encoded once if not) | – | – |
   | Apifon | API token | secret key | – | – |

   A missing required field answers `422` `{field: ["required"]}`, a malformed one `["invalid"]`,
   shown under the field (ADR-214). Infobip's base URL is checked against Infobip's own hosts
   (https, port 443, no path or user info), so a box cannot aim Palee's server at another host.
   Changing vendor never carries the previous vendor's credentials over; switching to Palee's
   account clears them all.
3. **Credentials** are stored like the Brevo key: `secret` and the new `webhook_secret`
   (migration `20270604000000`) are `EncryptedBinary`, redacted, never returned (the API says
   `has_secret` / `has_webhook_secret`), never logged, never put into error details or the attempt
   journal (adapter errors carry only `<vendor>_<code>`), excluded from tenant exports
   (`TenantDataPolicy.excluded_columns`). `account_id` (an identifier, not a secret) is shown.
4. **Delivery receipts** reach the box's one webhook URL (ADR-348 §5), passed per message:
   Twilio `StatusCallback`, Vonage `callback`, Infobip `webhooks.delivery.url`, Yuboto
   `callbackUrl` (with `dlr: true`), Apifon `callback_url`. Signatures, where the vendor offers
   them, are verified before anything is read:

   | Vendor | Signature |
   |---|---|
   | Twilio | always: `X-Twilio-Signature` = Base64(HMAC-SHA1(Auth Token, URL + sorted params)) |
   | Vonage | when the box saved the signature secret (Vonage support switches it on): `sig` over `&k=v` sorted params; MD5-hash or HMAC MD5/SHA-1/SHA-256/SHA-512, told apart by length |
   | Infobip, Yuboto, Apifon | none offered for per-message reports: the URL's secret token is the authentication (as for Brevo), and a receipt must name a message of this box |

   Yuboto calls back with a **GET**, so the webhook route also answers GET (same controller and
   rate limit).
5. **Error mapping** onto the port's kinds: refused credentials → `:unauthorized` (the connection
   is marked invalid, ADR-348); throttling, 5xx and "no credit" → `:transient` (retried, like
   Brevo's missing credits); anything that refuses this message (bad number, sender not approved,
   Twilio 21610 = the person replied STOP to Twilio) → `:rejected`; an unreadable answer →
   `:uncertain`. Per vendor: Twilio HTTP status and `code` (20003 credentials); Vonage per-part
   `status` (1, 5 throttled/internal → transient; 9 no balance → transient; 4, 14 →
   unauthorized; else rejected); Infobip HTTP status and `status.groupName` `REJECTED`; Yuboto
   `ErrorCode` (2, 23–25, 43–45 → unauthorized; 4, 22, 26 → transient; 108–111 sender; else
   rejected); Apifon HTTP status or `result_info.status_code` (401 → unauthorized).
6. **«Δοκιμή σύνδεσης»** calls something harmless with the credentials: Twilio `GET
   /Accounts/{sid}.json`, Vonage `GET /account/get-balance` (basic auth), Infobip `GET
   /account/1/balance`, Yuboto `POST /omni/v1/UserBalance`, Apifon `POST /services/api/v1/balance`
   (signed). It runs right after saving, as for Brevo.
7. **ADR-390 rules hold for every vendor unchanged**, because they live in the domain, not the
   adapter: no SMS leaves without the cap the box typed; quiet hours (21:00–09:00 by default,
   amended ADR-390) hold only offers; every offers SMS ends with the short unsubscribe link (a named
   sender cannot take a STOP reply). **Sender IDs**: every vendor takes up to 11 Latin letters,
   digits or spaces with at least one letter, or a number in E.164 (ADR-349); Twilio also takes a
   Messaging Service SID (`MG` + 32 hex, the service picks the sender; `sms_sender` grows to 40).
   Greek texts go as UCS-2 where the vendor needs to be told (Vonage `type=unicode`, Yuboto
   `typesms=unicode`, Apifon `dc=2`; Twilio and Infobip choose it themselves). Inbound STOP texts
   are honoured where a vendor forwards them to the box's URL (Twilio, Vonage, Infobip, Apifon
   two-way numbers).
8. **Cost**: a vendor's own price is used only when it states it in EUR (Infobip's report); all
   others (Twilio prices later and in USD, Vonage in the account currency, Yuboto and Apifon in
   their credits) keep the outbox's estimate, which the box sees against its cap (ADR-349/369; no
   Palee margin on an own account).
9. **UI** (decided screen, nothing else changed): Ρυθμίσεις › Συνδέσεις › Μηνύματα SMS ›
   «Προχωρημένα» › «Χρήση δικού μου παρόχου SMS» opens a `ui/Select` «Πάροχος SMS» (Brevo first),
   the chosen vendor's step-by-step guide (same style as Brevo's), and its fields; a saved secret
   of the same vendor may stay empty (kept). Errors stay in the form: required/invalid under the
   field before sending, the API's field reason under that field, and «Ο πάροχος X δεν δέχτηκε
   αυτά τα στοιχεία» under the key when the check refuses it (the form stays open).

## Rationale
One adapter per vendor keeps each vendor's quirks (signing, encodings, error codes) in one file
behind the port, testable with stubbed HTTP, and lets the domain rules (consent, cap, quiet hours,
unsubscribe link, outbox) stay vendor-free. A generic HTTP adapter would push request shapes,
signing and error mapping onto boxes, and could aim Palee's server anywhere.

## Alternatives Considered
- **Generic HTTP / template adapter**: rejected by ANR (security and support cost).
- **Routee, Modulus, Voiceland** (Greek): fewer developer-first APIs; can follow behind the same
  port.
- **Twilio and Vonage on Palee's account**: not asked; Palee's account stays Brevo (ADR-348).
- **Viber and WhatsApp through these vendors**: the port allows them, but ADR-348 keeps them for
  later; adapters say `channels: ["sms"]`.
- **Vonage Messages API (JWT)**: needs an application and private key per box; the SMS API with
  key and secret is simpler for a box to copy.
- **Infobip SMS API v2 (`/sms/2/text/advanced`)**: still documented, but v3 `/sms/3/messages`
  replaces it.

## Consequences
- `channel_connections.provider` accepts `twilio`, `vonage`, `infobip`, `yuboto`, `apifon`
  (check constraint); `webhook_secret` added; `sms_sender` 40 characters. `down` moves any such
  box back to Palee's Brevo account with SMS off.
- `GET /api/webhooks/channels/:organization_id/:token` added next to the POST.
- OpenAPI: `provider` enum widened, `webhook_secret` in the body, `has_webhook_secret` in the
  connection, `sms_sender` up to 40.
- The web's sender field (outside this section) still accepts only a name or a number; a Twilio
  Messaging Service SID can be set through the API only.
- Vendors' consoles, menus and names change; the guides need review when a vendor redesigns.

## Implementation Notes
- Domain: `Channels.Domain.VendorRules`. Adapters: `Infrastructure.Channels.{Twilio,Vonage,
  Infobip,Yuboto,Apifon}Channel`. `Channels.Connections` takes the vendor's fields, drops the
  others, and keeps saved secrets only for the same vendor.
- Web: `sms.ts` (`SMS_VENDORS`, `VENDOR_FIELDS`, `vendorFieldError`, `ownVendors`),
  `SmsConnectionSettings` `OwnAccount`; e2e `e2e/sms-own-vendors.spec.ts` (type-checked, not run).
- Sources (official API docs, read 2026-11-03):
  - Twilio: https://www.twilio.com/docs/messaging/api/message-resource ,
    https://www.twilio.com/docs/messaging/guides/track-outbound-message-status ,
    https://www.twilio.com/docs/usage/webhooks/webhooks-security ,
    https://www.twilio.com/docs/api/errors
  - Vonage: https://developer.vonage.com/en/api/sms ,
    https://developer.vonage.com/en/messaging/sms/guides/delivery-receipts ,
    https://developer.vonage.com/en/messaging/sms/guides/troubleshooting-sms ,
    https://developer.vonage.com/en/getting-started/concepts/signing-messages ,
    https://developer.vonage.com/en/api/account
  - Infobip: https://www.infobip.com/docs/api/channels/sms (OpenAPI
    https://api.infobip.com/platform/1/openapi/sms ),
    https://www.infobip.com/docs/essentials/api-essentials/response-status-and-error-codes ,
    https://www.infobip.com/docs/essentials/api-essentials/api-authentication
  - Yuboto OMNI API v1.10:
    https://octapush.yuboto.com/Data/pushc8b5-35c9-4b8c-9670-8f0dcb2ad364/OMNI_API_Documentation.pdf
    (§3.2 Authentication, §1 Send, §1.4 callbacks, §1.4.5 statuses, §5 User Balance, §16 errors)
  - Apifon: https://docs.apifon.com/authentication.html , https://docs.apifon.com/apireference.html
- Not verified against live accounts (no credentials): Vonage's hex case of `sig` (compared
  case-insensitively), whether Yuboto's `smsid` always equals the `Message[].id` of the send
  answer, and the exact console menu names in the guides.
