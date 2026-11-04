# Box websites on custom domains: what ops do (ADR-352, ADR-398)

A box adds its own domain under Staff › Settings › «Ιστοσελίδα». Palee checks
DNS and HTTPS by itself. Since ADR-398 the API also creates each verified
host's Ingress and cert-manager issues the certificate
(`BOX_SITE_INGRESS=kubernetes`); the manual steps below are the fallback
when that is off.

## Automatic (ADR-398)

- The API pod runs as ServiceAccount `palee-api` with a Role in `tenant-m4`
  only: ingresses (get, list, watch, create, update, patch, delete) and
  cert-manager certificates (get, list, watch), in gitops. The adapter needs
  nothing more (no secrets, no events).
- Each verified host (lower case) gets Ingress `palee-site-<20 hex of sha256(host)>`
  (label `palee.app/site=true`, annotation `palee.app/site-host: <host>`,
  `cert-manager.io/cluster-issuer: letsencrypt-production`,
  `spec.ingressClassName: nginx`, `spec.tls` with the host and secret
  `<name>-tls`), `/api` to `palee-api:4000` and `/` to `palee-web:3000`.
  Palee reads the Certificate of the secret's name (`Ready=True`).
- The cluster allows no namespaced Issuer: the defaults are
  `BOX_SITE_CERT_ISSUER_KIND=ClusterIssuer`,
  `BOX_SITE_CERT_ISSUER=letsencrypt-production`, `BOX_SITE_INGRESS_CLASS=nginx`.
- The Ingress is created only once DNS proves the host (TXT, and routing to
  `sites.palee.app`), so HTTP-01 does not fail and eat Let's Encrypt's
  rate limit. A resolver error or timeout counts as "unknown": the host keeps
  its state and is checked again in 5 minutes, its Ingress stays.
- Calls go through the outbox `box_site_ingress_ops` (retries 1 min → 6 h,
  8 tries). A nightly sweep (`BoxSiteIngressSweepJob`, 01:15 UTC = 03:15
  Athens in winter) deletes Palee's Ingresses whose host no box has any
  more, recreates missing ones and rereads active certificates. The
  5-minute checks read a Certificate only while it is still being issued.
- The card shows the certificate: «εκδίδεται», «έτοιμο» or a plain reason
  (`cluster_refused` means RBAC or a missing kind: check the Role and that
  the ClusterIssuer exists).
- `host_not_allowed`: the tenant policy rejected the Ingress (HTTP 400,
  "Policy tenant-ingress failed: host not allowed"): another tenant of the
  cluster owns the host, or it is a system domain. Final: tried once, never
  retried by checks or the sweep; the card says «Αυτό το domain δεν είναι
  διαθέσιμο…» and asks the owner to write to support. If the box really
  owns it, the cluster admin has to release it from the other tenant; then
  the owner removes the domain and adds it again.
- TLS secrets of removed hosts stay (no access to secrets). List them with
  `kubectl -n tenant-m4 get secret | grep palee-site-` and delete the ones
  without an Ingress.

Check from the cluster:

```
kubectl -n tenant-m4 get ingress -l palee.app/site=true
kubectl -n tenant-m4 get certificate,challenge
kubectl describe clusterissuer letsencrypt-production
kubectl -n tenant-m4 auth can-i create ingresses --as=system:serviceaccount:tenant-m4:palee-api
```

## States

| State | Meaning | Who acts |
|---|---|---|
| `pending_dns` | The box has not added the TXT proof and the CNAME (apex: CNAME flattening / ALIAS / ANAME) yet. Expires after 14 days. | The box |
| `pending_tls` | DNS proves the host is the box's and points at us. **It needs an Ingress.** | Ops |
| `active` | `https://<host>` answers. Rechecked daily. | – |
| `broken` | DNS or HTTPS stopped working; the site still answers at `/b/<slug>`. | The box (or ops if TLS) |

## One-time setup

1. The CNAME target: `sites.palee.app` CNAMEs to `prod.gata.4kq.net`, the
   only target the cluster supports (its IPs are not stable). Set
   `BOX_SITE_CNAME_TARGET` if it differs. There are no fixed addresses to
   configure: an apex host uses CNAME flattening / ALIAS / ANAME, and the
   check compares the host's A/AAAA with the target's A/AAAA resolved at
   that moment (every address of the host must be one of the target's).
2. Owners cannot add `palee.app`, `4kq.net`, `atha.gr`, `atha.io` or any
   name under them (refused when typed, `platform_hostname`).
3. cert-manager's `letsencrypt-production` ClusterIssuer with HTTP-01 is
   already allowed in `tenant-m4` (handoff 2026-10-26 §0.5).

## Manual fallback: for each host in `pending_tls`

List them (vendor account):

```
curl -H "Authorization: Bearer $TOKEN" https://palee.app/api/platform/site-domains?status=pending_tls
```

Add one Ingress per host in the gitops repo (`tenant-m4`), next to the `palee`
Ingress, routing `/api` and `/socket` to `palee-api` and everything else to
`palee-web`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site-www-mybox-gr            # site-<host with dots as dashes>
  namespace: tenant-m4
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
spec:
  ingressClassName: nginx
  tls:
    - hosts: [www.mybox.gr]
      secretName: site-www-mybox-gr-tls
  rules:
    - host: www.mybox.gr
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend: {service: {name: palee-api, port: {number: 4000}}}
          - path: /
            pathType: Prefix
            backend: {service: {name: palee-web, port: {number: 3000}}}
```

Within 5 minutes of the certificate being issued the `BoxSiteJob` probe
(`https://<host>/api/public/sites/by-host/<host>`) passes and the host becomes
`active`; the box can also press «Έλεγχος τώρα».

When a box removes a host or it is `expired`, delete its Ingress and secret.

## Self-hosted (Caddy)

Caddy can issue certificates by itself, but only for hosts Palee verified:

```
{
	on_demand_tls {
		ask http://api:4000/api/public/sites/tls-allowed
	}
}

https:// {
	tls {
		on_demand
	}
	reverse_proxy /api/* api:4000
	reverse_proxy web:3000
}
```

`tls-allowed?domain=<host>` answers 200 only for `pending_tls` and `active`
hosts, so nobody can make Caddy request certificates for other names.

## The web side

The Next.js proxy (`apps/web/src/proxy.ts`) maps an unknown `Host` to its box with
`GET /api/public/sites/by-host/<host>` (cached) and rewrites to the site
route; a non-primary host redirects (308) to `primary_host`.
