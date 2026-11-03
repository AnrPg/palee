# Box websites on custom domains: what ops do (ADR-352)

A box adds its own domain under Staff › Settings › «Ιστοσελίδα» (once the
screens exist; today `POST /api/org/:slug/admin/site/domains`). Palee checks
DNS and HTTPS by itself; ops only have to give each verified host a route and
a certificate.

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

## For each host in `pending_tls`

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

## The web side (after ANR approves the mockups)

The Next.js middleware maps an unknown `Host` to its box with
`GET /api/public/sites/by-host/<host>` (cached) and rewrites to the site
route; a non-primary host redirects (308) to `primary_host`.
