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
   `cert-manager.io/issuer: palee-sites` (a namespaced ACME Issuer with
   HTTP-01 on the default ingress class, in gitops); `BOX_SITE_CERT_ISSUER_KIND=ClusterIssuer`
   with `BOX_SITE_CERT_ISSUER=letsencrypt-production` switches to the
   cluster's issuer. Palee creates no Certificate itself, it only reads the
   one ingress-shim names after the secret.
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
6. **Sweep** (`BoxSiteIngressSweepJob`, hourly): Ingresses labelled as
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
   them.

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
- Apex hosts still need `BOX_SITE_A_RECORDS` (the ingress addresses) and
  `sites.palee.app` must resolve to the ingress.

## Implementation Notes
- Migration `20270606000000_box_site_ingresses.exs` (columns, the ops table,
  `palee_site_ingress_hosts()`, `palee_box_site_due_organizations` wakes boxes
  with due ops).
- Env (api container): `BOX_SITE_INGRESS=kubernetes`, optional
  `BOX_SITE_CERT_ISSUER_KIND`, `BOX_SITE_CERT_ISSUER`, `BOX_SITE_INGRESS_CLASS`,
  `BOX_SITE_KUBERNETES_API_URL` (default `https://kubernetes.default.svc`),
  `BOX_SITE_API_SERVICE`/`_PORT`, `BOX_SITE_WEB_SERVICE`/`_PORT`.
