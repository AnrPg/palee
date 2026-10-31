# ADR-381: Door access: a DoorController port, Shelly and Kisi, entry rules and the access log
Date: 2026-10-31
Status: Accepted (v3.2, CP-E3)

## Context
Many Greek boxes open early or run 24/7 open gym and hand out keys or keypad codes that never
expire. CP-E3 asks for a door-controller port with a sandbox, research on the systems Greek/EU
gyms use, one or two real adapters, rules for who may enter when, an audit log and offline
behaviour. Members already prove presence at the door for check-in (ADR-155: rotating QR on the
door screen, NFC tag, printed poster).

## Research (2026-10)
| System | How a third party opens | Fit for a Greek box |
|---|---|---|
| **Shelly** (Plus/Pro 1, Gen2/3 relays on a strike or magnetic lock) | Cloud Control API v2: `POST https://<server>/v2/devices/api/set/switch?auth_key=…` with `{id, channel, on: true, toggle_after: <s>}`; state via `/v2/devices/api/get`; ~1 request per second per account. The relay switches itself off after `toggle_after` even if the cloud link drops. | Cheapest (≈ €20–40 per door), sold everywhere in Greece, installed by any electrician. **Implemented.** |
| **Kisi** (cloud access control, readers + controller) | `POST https://api.kisi.io/locks/{id}/unlock`, header `Authorization: KISI-LOGIN <key>`; `409` when the lock has no online controller; webhooks for events. | Used by EU boutique gyms and coworkings; per-door subscription. **Implemented.** |
| **Nuki** (smart lock on the cylinder) | Web API `POST /smartlock/{id}/action` (`action: 1` unlock), Bearer token; asynchronous (the answer means "queued"). | Popular for small studios' front doors; needs a bridge for remote. Next adapter. |
| **Salto KS** | Connect API only through Salto's partner programme (contract, sandbox on request); or through Seam's API. | Larger chains and hotels-grade doors. Later, via partnership or Seam. |

Sources: docs.kisi.io (cloud unlocks, in-app unlocks), shelly-api-docs.shelly.cloud (Cloud Control
API v1/v2), docs.nuki.io and developer.nuki.io (Web API actions), developer.saltosystems.com
(KS Connect API), docs.seam.co (Salto via Seam), spacebring.com (Salto KS integration notes).

## Decision
1. **Port.** `Palee.Access.Ports.DoorController`: `unlock(controller, seconds)`, `check(controller)`,
   `parse_event(controller, params)`; failures are `{:offline | :unauthorized | :rejected, detail}`.
   Adapters: `SandboxDoorController` (dev/test, `simulate: "offline"`), `ShellyDoorController`,
   `KisiDoorController`; HTTP through `Palee.Infrastructure.Access.Http` (Req options from
   `config :palee, :door_http`, 4 s timeout; 401/403 → unauthorized, 429/5xx/timeouts → offline,
   other 4xx → rejected).
2. **Doors.** `door_controllers` (per branch, `facility_locations` FK): name, provider, settings
   (`server`, `device_id`, `channel` for Shelly; `lock_id` for Kisi), encrypted credentials
   (written, never read back), rules, status, last seen and error, and the hash of an **event token**
   for the controller's own notifications (`GET|POST /api/access/doors/:id/events?token=…`; Shelly
   actions call a URL with GET). The controller is checked before a door is saved.
3. **Entry rules** (pure, `Palee.Access.Domain.EntryRules`), in this order:
   staff of the box open any door at any hour (unless `staff_always: false`); a person who is not
   an active member never does (`not_a_member`); outside the door's opening hours (box's own time
   zone) members are refused (`outside_hours`); then `who`: `booked_or_covered` (default: a booking
   at this branch whose class starts 30′ before to 15′ after now, or a package covering open gym
   now), `members` (every active member, 24/7 boxes) or `staff_only`.
4. **Opening.** `POST /api/access/open` with the check-in scan's proof of presence
   (`location_id` + `code`, `nfc_code` or `poster_code`; `door_id` when a branch has several doors):
   presence → door → facts (`CheckInFacts`, roles) → rules → `unlock` for `unlock_seconds`
   (default 5). Opening does not check in; the app does both from one scan. Staff open from the
   desk (`POST /admin/doors/:id/unlock`, `check_in`).
5. **Offline: fail-secure.** If the controller cannot be reached the door stays locked, the member
   gets `door_offline` and is sent to the desk; nothing is queued to open later (a late opening
   is a security hole). The hardware's own fallback (a key, the keypad, Kisi's local credentials)
   stays the box's. Shelly's `toggle_after` makes the relay close itself even if the link drops
   mid-pulse.
6. **Access log.** `access_events`: `granted`, `denied` (with the reason), `unlock_failed`,
   `staff_unlock` (with who), `door_event` (controller notifications), method `qr|nfc|staff|provider`.
   Kept 180 days (purged hourly), visible to `manage_settings`, `manage_locations` and `check_in`,
   included in the member's data export, removed with the account.

## Rationale
Reusing ADR-155's proof of presence means no new credential (no PIN, no BLE key) and the rotating
QR already defeats sharing a screenshot. Cloud APIs keep Palee out of the building's LAN. Shelly is
the cheapest path for the typical Greek box; Kisi shows the port fits a real access-control vendor.

## Alternatives Considered
- **Member PINs on a keypad**: shared within minutes, no per-person log.
- **Local (LAN) control of the relay** from a box screen: needs a device on site and breaks when
  the screen is off; the cloud call is simpler and logs centrally.
- **Queueing unlocks while offline**: opens a door for nobody minutes later.
- **Seam as the single adapter**: one more processor and per-lock fees; kept as a later option for
  Salto.

## Consequences
- A box needs a cloud-connected controller; doors without internet keep their keys.
- Shelly's per-account rate limit (≈1 rps) makes a burst at 07:00 queue on Shelly's side; the 4 s
  timeout answers `door_offline` rather than leaving the member waiting.
- Follow-up: Nuki adapter; anti-passback; holding a door open for a class start; alarms on
  `door_event` "forced".

## Implementation Notes
- Migration `20270603000000_open_platform` (`door_controllers`, `access_events`); SECURITY DEFINER
  `palee_door_controller_lookup(uuid)` resolves a door's box for the event URL.
- Settings: `GET /admin/doors/catalog`, `GET|POST /admin/doors`, `PATCH|DELETE /admin/doors/:id`,
  `POST /admin/doors/:id/event-token`, `POST /admin/doors/:id/unlock`, `GET /admin/access-events`.
