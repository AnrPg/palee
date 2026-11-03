# ADR-398: Palee creates custom hosts' Ingresses; cert-manager issues the certificates
Date: 2026-11-03
Status: Accepted

## Context
ANR (W4 s2, v3.1 question 16 «cert-manager in v3.2»): a box may connect up
to 2 own domains (www and apex, one redirects to the other), free, and the
certificate is automatic. ADR-352 §6 and ADR-388 §6 left the Ingress per host
to ops (the `pending_tls` list, `docs/operations/box-site-custom-domains.md`)
because Palee did not talk to the cluster. Production runs ingress-nginx and
cert-manager in a tenant namespace (`tenant-m4`) without cluster-scope
access; the gitops repo already uses the `letsencrypt-production`
ClusterIssuer for `palee.app`.

## Decision
1. **Port and adapters.** `BoxSite.Ports.SiteIngress` (`apply_site/1`,
   `remove_site/1`, `certificate/1`, `managed_hosts/0`). The production
   adapter `KubernetesSiteIngress` calls the Kubernetes API with the pod's
   service account (in-cluster token and CA, Req with `req_options`), only in
   its own namespace. `SandboxSiteIngress` serves dev and test. With no
   adapter (`config :palee, :box_site_ingress, nil`, the default outside dev
   and test unless `BOX_SITE_INGRESS=kubernetes`) nothing changes: the manual
   list and Caddy's `ask` stay the fallback.
2. **One Ingress per verified host**, named `palee-site-<sha256(host)[0..20]>`,
   label `palee.app/site=true`, the host in annotation `palee.app/site-host`,
   TLS secret `<name>-tls`. `/api` → `palee-api:4000`, `/` → `palee-web:3000`
   (the TLS probe and the site forms need `/api`; the web proxy serves the
   site by `Host` and sends a secondary host to the primary one with a 308,
   ADR-388). Applied with server-side apply (`fieldManager=palee-api`).
3. **Certificates through ingress-shim.** The Ingress carries
   `cert-manager.io/cluster-issuer: letsencrypt-production` and
   `spec.ingressClassName: nginx` (superseded defaults: see the follow-up of
   2026-11-03; the namespaced `palee-sites` Issuer is not allowed). Palee
   creates no Certificate itself, it only reads the one ingress-shim names
   after the secret.
4. **When.** A host has an Ingress while its domain is `pending_tls`,
   `active` or `broken`: the check that proves DNS queues `apply`; falling
   back to `pending_dns`, expiring or removal queues `delete`. A check also
   re-queues a verified host that has none (verified before this ADR, or
   refused by the cluster on every try) and otherwise reads its certificate.
5. **Outbox** `box_site_ingress_ops` (tenant table, forced RLS): one waiting
   op per host (a newer one replaces it), claimed with `FOR UPDATE SKIP LOCKED`,
   a host with an op in flight is skipped. Retries after 1 min, 5 min,
   15 min, 1 h, then every 6 h; after 8 tries the op is `failed`. It runs at
   once after it is queued (`BoxSiteJob` for the box) and with the 5-minute
   cron. Deletes keep the host, so they outlive the domain row.
6. **Sweep** (`BoxSiteIngressSweepJob`, nightly at 01:15 UTC, 03:15 in
   Athens in winter; hourly until the 2026-11-03 follow-up): Ingresses labelled as
   Palee's whose host no box has any more (a box that left, a lost op) are
   deleted; verified hosts without one get it again. It reads the cluster
   before the database, so a host verified meanwhile is never taken for an
   orphan. `palee_site_ingress_hosts()` (SECURITY DEFINER, `search_path`
   only) gives the hosts across boxes.
7. **Card status.** `box_site_domains.certificate_status`
   (`none pending issuing active failed`) and `certificate_error`
   (`cluster_refused cluster_unreachable challenge_failed rate_limited issuer_not_ready issuance_failed`)
   are returned with each domain. The card adds one line under the existing
   steps: «Το πιστοποιητικό εκδίδεται…», «Πιστοποιητικό ενεργό» or a plain
   reason. cert-manager retries its own failures; Palee does not re-apply for
   them. Checks read the certificate only while it is not active yet
   (`issuing`, or `failed` for a cert-manager reason); active certificates
   are reread by the nightly sweep (2026-11-03 follow-up).

## Rationale
cert-manager already issues and renews `palee.app`'s certificate in the same
namespace; creating an Ingress is the smallest step that makes it do the
same for a box's host, with RBAC limited to ingresses (and reading
certificates) in one namespace. The outbox and sweep follow the fiscal and
payments pattern: the request that proves DNS never waits on the cluster,
and the cluster converges even if a call or a row is lost.

## Alternatives Considered
- A Certificate resource per host created by Palee: more RBAC and two objects
  to keep in step, while ingress-shim does it from the annotation.
- One Ingress for both hosts of a box with nginx's `from-to-www-redirect`:
  the hosts verify at different times and the redirect is already done by the
  web for any primary/secondary pair (not only www/apex).
- An in-cluster controller watching a CRD: needs cluster-scope installs the
  tenant does not have.
- Issuing certificates in the API (ACME client): rejected in ADR-352.

## Consequences
- The API pod gets a service account token (`palee-api` ServiceAccount, Role
  and RoleBinding in gitops); the cluster admin must allow what the tenant
  cannot do itself (see `docs/operations/box-site-custom-domains.md`).
- TLS secrets of removed hosts stay until cert-manager or ops delete them
  (Palee's Role has no access to secrets); they expire within 90 days.
- ~~Apex hosts still need `BOX_SITE_A_RECORDS`~~ (removed 2026-11-03: apex
  hosts use CNAME flattening / ALIAS / ANAME); `sites.palee.app` must keep
  CNAME-ing to the cluster's name.

## Implementation Notes
- Migration `20270606000000_box_site_ingresses.exs` (columns, the ops table,
  `palee_site_ingress_hosts()`, `palee_box_site_due_organizations` wakes boxes
  with due ops).
- Env (api container): `BOX_SITE_INGRESS=kubernetes`, optional
  `BOX_SITE_CERT_ISSUER_KIND` (default `ClusterIssuer`), `BOX_SITE_CERT_ISSUER`
  (default `letsencrypt-production`), `BOX_SITE_INGRESS_CLASS` (default `nginx`),
  `BOX_SITE_KUBERNETES_API_URL` (default `https://kubernetes.default.svc`),
  `BOX_SITE_API_SERVICE`/`_PORT`, `BOX_SITE_WEB_SERVICE`/`_PORT`.

## Follow-up 2026-11-03: the cluster's sysadmin answered
Facts from the cluster admin, and what changed:

1. **The cluster's addresses are not stable.** The only supported target is
   a CNAME to `prod.gata.4kq.net`; `sites.palee.app` (`BOX_SITE_CNAME_TARGET`)
   already CNAMEs there, so owners point at `sites.palee.app`.
   `BOX_SITE_A_RECORDS` and every fixed-IP instruction are gone. A `www`
   (non-apex) host gets a CNAME record; an apex host gets an `ALIAS` record
   in the card and the instructions email («CNAME flattening / ALIAS /
   ANAME», whatever the provider calls it) to the same target.
2. **The DNS check resolves the target live.** A host points at Palee when
   its CNAME chain (followed hop by hop, up to 8) reaches the target, or
   when it has at least one address and **every** A and AAAA it has is among
   the target's A and AAAA **at that moment**. Why "every" and not "any":
   a stray or stale address sends some visitors, and Let's Encrypt's HTTP-01
   validator, somewhere else, which fails issuance and burns rate limit.
   Why a subset and not equality: a flattening provider may answer with
   fewer addresses than the target has, and nodes come and go, so requiring
   the full set would flap during a rollout. When the nodes change, a
   flattened apex follows within its provider's TTL; until it does it may
   fail one check (`active` → `broken`, which keeps serving and its Ingress)
   and recovers on the next.
3. **Unknown is not failure.** `Ports.DomainDns.lookup/2` now answers
   `{:ok, values}` (NXDOMAIN and "no such record" are `{:ok, []}`) or
   `{:error, reason}` (timeout, SERVFAIL). `DomainPolicy.dns_facts/3`
   gives `true | false | :unknown`; an unknown fact (or the target itself
   resolving to nothing) keeps the host's state and checks again in 5
   minutes, without counting a failed attempt. So a resolver hiccup never
   sends a `pending_tls` host back to `pending_dns` and never deletes and
   recreates its Ingress. A definite answer that no longer points here
   keeps the earlier behaviour (`pending_tls` → `pending_dns` deletes the
   Ingress; `active` → `broken` keeps it). The resolver stays behind the
   port; tests use `SandboxDomainDns` (which can answer `{:error, _}`).
4. **The Ingress is created only after the check passes.** Verified: the
   only `apply` comes from `pending_dns` → `pending_tls|active` (TXT and
   routing both `true`), the re-queue of a verified host without one, and
   the sweep of verified hosts. No change needed.
5. **No namespaced Issuer.** Defaults are now `BOX_SITE_CERT_ISSUER_KIND=ClusterIssuer`,
   `BOX_SITE_CERT_ISSUER=letsencrypt-production`, `BOX_SITE_INGRESS_CLASS=nginx`:
   `spec.ingressClassName: nginx`, annotation `cert-manager.io/cluster-issuer`,
   `spec.tls` with the same host and one `secretName` per host
   (`palee-site-<hash>-tls`). The certificate is read from the Certificate of
   that name (ingress-shim's naming), `Ready=True` → active.
6. **Hosts are lower case**, on input (`Hostname.normalize/2`) and again in
   the adapter (names, annotation, rules, TLS). The tenant allows
   `palee.app`, `*.palee.app`, `milos.4kq.net`, `*.milos.4kq.net` and any
   customer domain no other tenant claims, outside the system domains
   `4kq.net`, `atha.gr`, `atha.io`. A box may claim none of `palee.app`,
   `4kq.net`, `atha.gr`, `atha.io` or anything under them
   (`Hostname.system_suffixes/0`, always on, whatever the config); the web
   form says so under the field before it sends anything, and the API
   answers `422 platform_hostname`.
7. **"Host not allowed" is final.** The tenant policy rejects an Ingress
   whose host another tenant owns with HTTP 400 and a message containing
   `Policy tenant-ingress failed: host not allowed`. The adapter answers
   `{:error, :host_not_allowed}`; the op becomes `failed` after one try
   (no 8-try loop); the domain shows `certificate_status=failed`,
   `certificate_error=host_not_allowed` («Αυτό το domain δεν είναι
   διαθέσιμο…», likely another customer of the hosting or a system domain,
   write to support). Checks neither re-queue nor delete for it, and
   `palee_site_ingress_hosts()` leaves it out so the sweep does not recreate
   it (migration `20270704100000_box_site_host_not_allowed.exs`). Removing
   the domain and adding it again starts fresh.
8. **www → apex** stays the web's 308 from a secondary to the primary host
   (ADR-388), for any pair. ingress-nginx's `from-to-www-redirect`
   annotation would do it at the edge for www/apex only, but needs both
   hosts on one Ingress and both verified at once; not used.
9. **RBAC** (now in gitops): ingresses get/list/watch/create/update/patch/delete
   and cert-manager.io certificates get/list/watch. The adapter uses
   ingresses patch (server-side apply, creating when missing), delete and
   list, and certificates get; nothing else (no secrets, events or other
   kinds). TLS secrets of removed hosts still stay for ops to clean.
10. **Less polling of the cluster** (product owner, same day). The sweep runs
    once a night (`15 1 * * *`; the Oban cron has no timezone, so UTC:
    03:15 in Athens in winter, 04:15 in summer) instead of hourly. A lost op
    or an orphan Ingress now waits at most a day, which is fine: ops already
    run at once and retry on their own. The 5-minute `BoxSiteJob` checks read
    a host's Certificate only while it is not active (`issuing`, or `failed`
    with a reason cert-manager retries); an active one is reread by the
    nightly sweep, for the hosts whose Ingress it found, and a renewal that
    went wrong then shows on the card. `palee_site_ingress_hosts()` returns
    the domain's id and `certificate_status` for that. Every other cluster
    call is an op (apply/delete) that runs once, plus its retries.
