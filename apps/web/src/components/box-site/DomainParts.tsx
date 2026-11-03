"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { SiteDomain } from "@/api/box-site";

export type DnsRecord = SiteDomain["dns_records"][number];
type Status = SiteDomain["status"];

const STEP_OF: Record<Status, number> = { pending_dns: 1, pending_tls: 2, active: 3, broken: 1, expired: 1 };

/** «Βήματα»: 1 the records, 2 the certificate, 3 live (ANR s2 A). */
export function DomainSteps({ status }: { status: string }) {
  const t = useTranslations("BoxSite");
  const current = STEP_OF[status as Status] ?? 1;
  return (
    <ol className="flex flex-col gap-1.5 text-sm sm:flex-row sm:gap-4" data-testid="site-domain-steps">
      {[1, 2, 3].map((step) => {
        const done = step < current || (step === 3 && status === "active");
        const now = step === current && !done;
        return (
          <li key={step} className="flex items-center gap-2" aria-current={now ? "step" : undefined}>
            <span
              aria-hidden="true"
              className="grid h-6 w-6 place-items-center rounded-full text-xs font-extrabold"
              style={done ? { background: "var(--success)", color: "var(--success-contrast)" } : now ? { border: "2px solid var(--primary)", color: "var(--text)" } : { border: "1px solid var(--border)", color: "var(--dim)" }}
            >
              {done ? "✓" : step}
            </span>
            <span style={{ color: now || done ? "var(--text)" : "var(--dim)" }}>{t(`domains.step${step}`)}</span>
          </li>
        );
      })}
    </ol>
  );
}

const CERTIFICATE_ERRORS = ["cluster_refused", "cluster_unreachable", "challenge_failed", "rate_limited", "issuer_not_ready", "issuance_failed", "host_not_allowed"];

/** ADR-398: domains no box may claim (the API refuses them too, `Hostname.system_suffixes/0`). */
export const SYSTEM_DOMAINS = ["palee.app", "4kq.net", "atha.gr", "atha.io"];

/** Whether a typed host is one of the system domains or under one. */
export function isSystemHost(input: string) {
  const host = input.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/+$/, "").replace(/\.$/, "");
  return SYSTEM_DOMAINS.some((suffix) => host === suffix || host.endsWith(`.${suffix}`));
}

/**
 * ADR-398: the certificate's line under the status, or null. Shown once Palee
 * made the Ingress (not `none`); once the domain is active only a failure is
 * worth a line. A known certificate state replaces the generic TLS reason.
 */
export function certificateLine(status: string, certificateStatus: string | null | undefined, certificateError: string | null | undefined) {
  // The cluster will never route it: said whatever the DNS state, until the owner removes it.
  if (certificateStatus === "failed" && certificateError === "host_not_allowed" && status !== "expired") return { key: "domains.certificateError.host_not_allowed", tone: "danger" as const };
  if (!certificateStatus || certificateStatus === "none" || status === "pending_dns" || status === "expired") return null;
  const error = certificateError && CERTIFICATE_ERRORS.includes(certificateError) ? certificateError : null;
  if (certificateStatus === "failed") return { key: `domains.certificateError.${error ?? "issuance_failed"}`, tone: "danger" as const };
  if (status === "active") return null;
  if (certificateStatus === "pending" && error) return { key: `domains.certificateError.${error}`, tone: "warning" as const };
  if (["pending", "issuing", "active"].includes(certificateStatus)) return { key: `domains.certificate.${certificateStatus}`, tone: "neutral" as const };
  return null;
}

/** One line on where the domain stands, with the reason when it is stuck. */
export function DomainStatusLine({
  status,
  lastError,
  certificateStatus,
  certificateError,
}: {
  status: string;
  lastError: string | null;
  certificateStatus?: string | null;
  certificateError?: string | null;
}) {
  const t = useTranslations("BoxSite");
  const known = ["pending_dns", "pending_tls", "active", "broken", "expired"].includes(status) ? status : "pending_dns";
  const tone = known === "active" ? "var(--success)" : known === "broken" || known === "expired" ? "var(--danger)" : "var(--warning)";
  const certificate = certificateLine(known, certificateStatus, certificateError);
  const tlsReasons = certificate ? [] : ["tls_not_ready", "tls_failed"];
  const reason = lastError && ["dns_txt_missing", "dns_not_pointing", ...tlsReasons].includes(lastError) ? lastError : null;
  return (
    <div className="flex flex-col gap-1" data-testid="site-domain-status-line">
      <DomainSteps status={known} />
      <p className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
        <span aria-hidden="true" className="h-2.5 w-2.5 rounded-full" style={{ background: tone }} />
        {t(`domains.status.${known}`)}
      </p>
      {reason && known !== "active" ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`domains.error.${reason}`)}</p> : null}
      {certificate ? (
        <p className="text-sm" style={{ color: certificate.tone === "danger" ? "var(--danger)" : "var(--text-soft)" }} data-testid="site-domain-certificate">
          {t(certificate.key)}
        </p>
      ) : null}
    </div>
  );
}

/** The DNS records to add, each with «Αντιγραφή». */
export function DnsRecords({ records }: { records: DnsRecord[] }) {
  const t = useTranslations("BoxSite");
  if (records.length === 0) return null;
  return (
    <div className="flex flex-col gap-2" data-testid="site-dns-records">
      <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("domains.recordsTitle")}</p>
      <ul className="flex flex-col gap-2">
        {records.map((record) => (
          <li key={`${record.type}-${record.name}-${record.value}`} className="grid gap-1 rounded-2xl p-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <span className="text-xs font-bold" style={{ color: "var(--dim)" }}>{record.type === "ALIAS" ? t("domains.aliasType") : record.type}</span>
            <RecordValue label={t("domains.recordName")} value={record.name} />
            <RecordValue label={t("domains.recordValue")} value={record.value} />
            {record.type === "ALIAS" ? (
              <span className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="site-dns-alias-hint">
                {t("domains.aliasHint")}
              </span>
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}

function RecordValue({ label, value }: { label: string; value: string }) {
  const t = useTranslations("BoxSite");
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  }
  return (
    <span className="flex items-center gap-2">
      <span className="w-14 shrink-0 text-xs" style={{ color: "var(--dim)" }}>{label}</span>
      <code className="min-w-0 flex-1 break-all text-[13px]" style={{ color: "var(--text)" }}>{value}</code>
      <button type="button" onClick={() => void copy()} className="min-h-9 shrink-0 px-2 text-xs font-bold" style={{ color: "var(--primary-strong)" }}>
        {copied ? t("domains.copied") : t("domains.copy")}
      </button>
    </span>
  );
}
