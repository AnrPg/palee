# ADR-375: The watch companion (Apple Watch, Wear OS)
Date: 2026-10-31
Status: Accepted (server side and contract); native apps pending

## Context
CP-D8 (P2, L): the timer and heart rate on the wrist (BTWB has it). Garmin
already syncs finished workouts (ADR-161); the store apps are a Capacitor
shell (ADR-171) with native plugins (health, widgets, NFC). ANR has not yet
chosen which watch platform comes first (plan, open decision 5).

## Decision
1. **Topology**: the watch app talks only to the phone app
   (WatchConnectivity on watchOS, the Wearable Data Layer on Wear OS); the
   phone calls Palee with the person's session. The server never talks to
   Apple or Google for the watch, so there is no watch-provider port and no
   watch credentials; push to the watch rides on the existing native push
   (ADR-171) to the phone.
2. **Shared contract, version 1** (`Devices.Domain.WatchContract`):
   - the **watch plan** (`GET /api/executions/:id/watch-plan?platform=`):
     compact segments (kind, phase, duration, round/total, label key and
     params, up to 3 movements), current progress with `lock_version`, the
     pace line of ADR-374 (`at_ms` per checkpoint), the commands, heart-rate
     settings (interval 5 s, `max_hr`) and haptics;
   - **commands** `next`, `round`, `pause`, `resume`, `finish`: the phone
     turns each into the existing idempotent calls (progress with
     `operation_id`, split marks, completion);
   - **heart rate**: numbered batches (`sequence`, offset, interval, up to 720
     bpm values) via `POST /api/executions/:id/heart-rate`, stored once each;
     `GET` returns average, max, min, per section and, with `max_hr`, time in
     five zones;
   - **pairing** (`GET /api/me/devices/watches`, `PUT|DELETE
     /api/me/devices/watches/:platform`): device name, app and contract
     versions, settings (`show_heart_rate`, `show_pace`, `haptics`,
     `max_hr`). A watch speaking an unsupported contract gets **426
     `watch_upgrade_required`**.
3. **Offline**: the watch runs from the plan it holds, queues commands,
   marks and heart-rate batches in order; the phone sends them later. Every
   write is idempotent (operation ids, `(execution, segment, round)`,
   `(execution, sequence)`).
4. **Privacy**: heart rate is health data — stored only with the
   `health_data` consent (ADR-158/159), visible only to the person
   (owner-only RLS), in the GDPR export, deleted with the account (also when
   the profile is kept anonymised). Samples outside 25–250 bpm are ignored in
   summaries.

## Rationale
A phone relay is how both platforms are designed (watch apps without their
own network are the norm and need no second sign-in). Reusing the
execution's idempotent calls means one source of truth for the timer, the
same one the web and the box screen read.

## Alternatives Considered
- Standalone watch apps calling the API (LTE watches): a second token store
  on the watch and duplicated offline logic. Later, behind the same contract.
- HealthKit/Health Connect workout sessions only (no Palee watch app): gives
  heart rate after the fact (already possible through ADR-172), not the
  timer on the wrist. Rejected as the main path, kept as a fallback.

## Consequences
Native work that remains (needs Xcode / Android Studio on the owner's
machine; nothing here builds it):
- **watchOS**: a watchOS app target + WatchKit extension in
  `apps/mobile/ios/App` (SwiftUI timer screen, `HKWorkoutSession` for live
  heart rate, `WCSession` to the phone), an iOS-side Capacitor plugin
  `PaleeWatch` (send plan, receive commands/marks/batches, forward to the
  API with the session), entitlements (HealthKit on the watch), App Store
  review of the watch app.
- **Wear OS**: a `:wear` Gradle module in `apps/mobile/android` (Compose for
  Wear OS timer, Health Services `ExerciseClient` for heart rate, Data Layer
  `MessageClient`/`DataClient`), the phone-side plugin, Play Console
  form-factor listing.
- Both: contract tests in the plugins against the OpenAPI schemas
  `WatchPlan` and `HeartRateBatchesRequest`.

## Implementation Notes
- Tables `watch_links`, `execution_heart_rate_batches` (migration
  `20270602200000`), `Palee.Application.WatchCompanion`, `WatchController`.
- The native targets were not scaffolded in the repo: an un-buildable
  Xcode target or Gradle module would break `cap sync` and CI for everyone.
