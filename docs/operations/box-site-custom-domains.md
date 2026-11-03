# Box websites on custom domains: what ops do (ADR-352, ADR-398)

A box adds its own domain under Staff › Settings › «Ιστοσελίδα». Palee checks
DNS and HTTPS by itself. Since ADR-398 the API also creates each verified
host's Ingress and cert-manager issues the certificate
(`BOX_SITE_INGRESS=kubernetes`); the manual steps below are the fallback
when that is off.

## Automatic (ADR-398)

- The API pod runs as ServiceAccount `palee-api` with a Role in `tenant-m4`
  only: ingresses (get, list, create, patch, update, delete) and
  cert-manager certificates (get, list). Gitops: `palee/palee-api-rbac.yaml`.
- Each verified host gets Ingress `palee-site-<20 hex of sha256(host)>`
  (label `palee.app/site=true`, annotation `palee.app/site-host: <host>`,
  `cert-manager.io/issuer: palee-sites`, TLS secret `<name>-tls`), `/api` to
  `palee-api:4000` and `/` to `palee-web:3000`.
- `palee-sites` is a namespaced ACME Issuer (HTTP-01, default ingress class),
  gitops `palee/palee-sites-issuer.yaml`. To use the cluster's issuer
  instead: `BOX_SITE_CERT_ISSUER_KIND=ClusterIssuer`,
  `BOX_SITE_CERT_ISSUER=letsencrypt-production`.
- Calls go through the outbox `box_site_ingress_ops` (retries 1 min → 6 h,
  8 tries). An hourly sweep deletes Palee's Ingresses whose host no box has
  any more and recreates missing ones.
- The card shows the certificate: «εκδίδεται», «έτοιμο» or a plain reason
  (`cluster_refused` means RBAC or a missing kind: check the Role and that
  the Issuer exists).
- TLS secrets of removed hosts stay (no access to secrets). List them with
  `kubectl -n tenant-m4 get secret | grep palee-site-` and delete the ones
  without an Ingress.

Check from the cluster:

```
kubectl -n tenant-m4 get ingress -l palee.app/site=true
kubectl -n tenant-m4 get certificate,challenge
kubectl -n tenant-m4 describe issuer palee-sites
kubectl -n tenant-m4 auth can-i create ingresses --as=system:serviceaccount:tenant-m4:palee-api
```

## States

| State | Meaning | Who acts |
|---|---|---|
| `pending_dns` | The box has not added the TXT proof and the CNAME/A records yet. Expires after 14 days. | The box |
| `pending_tls` | DNS proves the host is the box's and points at us. **It needs an Ingress.** | Ops |
| `active` | `https://<host>` answers. Rechecked daily. | – |
| `broken` | DNS or HTTPS stopped working; the site still answers at `/b/<slug>`. | The box (or ops if TLS) |

## One-time setup

1. A DNS name for the CNAME target: `sites.palee.app` → the ingress load
   balancer (A/AAAA). Set `BOX_SITE_CNAME_TARGET` if it differs.
2. The ingress addresses for apex hosts (which cannot have a CNAME):
   `BOX_SITE_A_RECORDS=203.0.113.10,203.0.113.11` on the `api` container.
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
