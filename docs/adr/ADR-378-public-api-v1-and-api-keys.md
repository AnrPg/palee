# ADR-378: Public API v1, per-box API keys and the first operations of the registry
Date: 2026-10-31
Status: Accepted (v3.2, CP-F5; first step of ADR-300 and ADR-301)

## Context
Boxes ask to connect Palee to the tools they already use (a CRM, Zapier/Make, a spreadsheet, their
own website). CP-F5 asks for per-box keys with scopes and rotation, a versioned read/write API
for members, bookings, classes and packages (payments read-only), idempotency, rate limits and an
OpenAPI document. v4 (ADR-300/301) will expose every use case to agents through one operation
registry and treat agents as delegated principals. Building the public API as a separate set of
hand-written controllers would create the "parallel system" ADR-300 exists to prevent.

## Decision
1. **The registry starts here.** `Palee.Operations.Operation` (`spec/0`, `execute/2`, optional
   `preview/2`) and `Palee.Operations` (registry from `config :palee, :operations`, contract check,
   routes) are the ADR-300 behaviour, unchanged in shape. Fifteen v1 operations are the seed:
   `members.list|get|invite`, `classes.list|get|create`, `bookings.list|create|cancel`,
   `packages.list`, `member_packages.assign`, `payments.list` (read only), `key.describe` (`GET /me`),
   `webhook_subscriptions.create|delete` (ADR-379). Each one calls an existing application service
   (`ListAdminUsers`, `PlaceMemberInClass`, `WithdrawBooking`, `AssignFinanceMemberPackage`, ...):
   the public API adds no business rule of its own.
2. **One runner.** `Palee.Application.Operations.Runner.run/4`: policy (the key's scope AND one of
   the spec's capabilities, read now) → JSON Schema 2020-12 cast (`Palee.Operations.Domain.JsonSchema`,
   strings coerced from query parameters) → idempotency for commands → `execute` or `preview`.
   The same runner will serve MCP and in-app agents in v4.
3. **Routes and document are generated.** The router builds `/api/public/v1/*` from
   `Palee.Operations.routes/0` at compile time; `GET /api/public/v1/openapi.json` (no key) is an
   OpenAPI 3.1 document generated from the specs (`PaleeWeb.PublicApiSpec`), with the webhook events
   under 3.1's `webhooks`. Palee's own OpenAPI document (ADR-134) does not include these routes.
   (The plan wrote `/public/v1`; the public base URL serves `/api`, hence `/api/public/v1`.)
4. **API keys.** `palee_<live|test>_<12-char prefix>_<40-char secret>` (base32, 260 bits). Only
   the SHA-256 of the secret and the prefix are stored (`api_keys`); lookup by prefix through the
   SECURITY DEFINER `palee_api_key_lookup(text)`, then a constant-time compare. Shown once. Up to
   25 active keys per box, optional expiry, revoke at once. **Rotation** keeps the prefix and
   accepts the previous secret for 24 hours, so an integration can be updated without downtime.
5. **A key is a delegated principal (ADR-301 without the agent).** A key acts for the staff member
   who made it: each request rebuilds that person's tenant context as of now
   (`resolve_tenant_context_by_id`) and sets `principal: %{kind: :api_key, ...}`. Rights are the
   person's current capabilities ∩ the key's scopes, so a key can never do more than its maker and
   stops working the moment they leave the box or lose the role. Scopes: `members:read|write`,
   `classes:read|write`, `bookings:read|write`, `packages:read|write`, `payments:read`,
   `webhooks:write`; `write` never implies `read`. Only `manage_settings` (owners, admins) makes keys.
6. **Idempotency (ADR-300 §5).** A command with `Idempotency-Key` (1–255 visible ASCII) runs
   once per principal and key: `idempotency_records` holds the request fingerprint (SHA-256 of the
   operation and its canonical JSON input) and the first answer for 24 hours; the same key and body
   answer again with `Idempotent-Replayed: true`; another body is `409 idempotency_key_reused`; a
   key still running is `409 idempotency_key_in_use`; a refusal frees the key. Purged hourly.
7. **Preview.** `Palee-Preview: true` on a command answers the operation's `preview/2` and writes
   nothing (ADR-300 §4).
8. **Errors** are RFC 9457 problem details (`application/problem+json`, `type
   urn:palee:problem:<code>`, `title`, `status`, `code`, `params`/`errors`) made from the same
   stable codes as the rest of Palee by `PaleeWeb.Plugs.ProblemDetails`.
9. **Rate limit**: 120 requests per minute per key and HTTP method, whatever the caller's address
   (`RateLimit` gained `per_actor: true`, since Zapier and Make call from many addresses).
10. **Representations are whitelisted** in `Palee.Application.Operations.Views`; cursor pages
    (`data`, `next_cursor`); UTC ISO 8601; money in cents with currency.

## Rationale
Starting the registry with a real consumer (the public API) proves the spec shape, the runner and
the generated routes before agents depend on them, and every later operation becomes available to
Zapier, MCP and agents at once. Recomputing rights on every call avoids long-lived tokens that
outlive a staff member's role.

## Alternatives Considered
- **Hand-written `/public/v1` controllers with OpenApiSpex.** Faster today, but a second copy of
  every schema and exactly the duplication ADR-300 rejects.
- **OAuth 2.0 client credentials / authorization code now.** Zapier and Make support API-key
  auth well; OAuth needs app registration, consent screens and refresh-token storage. Deferred to
  v4's MCP work (OAuth 2.1 + PKCE, ADR-301), which needs it anyway; keys and scopes carry over as
  the consent's scopes.
- **Keys as their own principals with their own role.** Breaks "never more than its maker" and
  needs a second permission model.
- **Per-IP rate limits.** Integration platforms share and rotate addresses.

## Consequences
- The router has a compile-time dependency on the operation modules (their `spec/0`).
- Adding a public operation = a module + a config line + a contract test pass; the route and the
  OpenAPI document follow.
- `TenantContext` gains `principal` (nil for people).
- Follow-up (v4): ETags, `next_actions`, agent audit rows, MCP surface, OAuth 2.1, versions > 1.

## Implementation Notes
- Migration `20270603000000_open_platform` (tables `api_keys`, `idempotency_records`, plus ADR-379..381's).
- Settings: `GET|POST /admin/integrations/api-keys`, `POST .../:id/rotate`, `DELETE .../:id`.
- `members.invite` is `risk: :outward` (it emails a person); `member_packages.assign` is `:money`.
- `classes.list` reads at most 31 days per call.
