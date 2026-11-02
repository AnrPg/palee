"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchDomainStatus } from "@/api/box-site";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { DnsRecords, DomainStatusLine, type DnsRecord } from "./DomainParts";

/** What the person who runs the box's domain sees from the emailed link. */
export function DomainStatusPage({ token }: { token: string }) {
  const t = useTranslations("BoxSite");
  const query = useQuery({ queryKey: ["public", "site-domain", token], queryFn: () => fetchDomainStatus(token), retry: false, refetchInterval: 60_000 });
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-col gap-5 px-4 py-10" data-testid="site-domain-status">
      {query.isPending ? <div className="h-40 animate-pulse rounded-3xl" style={{ background: "var(--panel-raised)" }} /> : null}
      {query.isError ? <ErrorNotice>{t("domains.linkExpired")}</ErrorNotice> : null}
      {query.data ? (
        <>
          <header className="flex flex-col gap-1">
            <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{query.data.host}</h1>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("domains.statusIntro", { box: query.data.box_name })}</p>
          </header>
          <DomainStatusLine status={query.data.status} lastError={query.data.last_error} />
          <DnsRecords records={query.data.dns_records as DnsRecord[]} />
        </>
      ) : null}
    </main>
  );
}
