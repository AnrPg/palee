"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState } from "react";

import { atRiskKey, atRiskMemberKey, fetchMemberAtRisk, fetchMembersAtRisk, type RiskFilter } from "@/api/leads";
import { PageHeader } from "@/components/PageHeader";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { useGymTime, useLeadErrorText } from "@/components/admin/leads/leads-ui";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { BackLink } from "@/components/ui/BackLink";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { AtRiskRow } from "./AtRiskRow";
import { personName, reasonLine, sortedReasons } from "./risk-model";

/**
 * Μέλη › «Σε κίνδυνο» (ADR-347, W2 p4 A): who may be leaving, why, and
 * what to do, with «Επικοινώνησα» and «Αργότερα» on each row. A row opens
 * the member's reasons and the log of what staff did (ADR-384).
 */
export function MembersAtRisk() {
  const t = useTranslations("AtRisk");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const errorText = useLeadErrorText();
  const [level, setLevel] = useState<RiskFilter>("all");
  const [open, setOpen] = useState<string | null>(null);

  const list = useQuery({
    queryKey: atRiskKey(level),
    enabled: Boolean(token),
    queryFn: () => fetchMembersAtRisk(token!, level),
  });
  const counts = list.data?.counts ?? {};
  const high = counts.high ?? 0;
  const medium = counts.medium ?? 0;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-4xl space-y-6">
        <BackLink href={adminHref("/admin/users", slug)}>{t("backToMembers")}</BackLink>
        <PageHeader title={t("title")} />
        <SegmentPicker<RiskFilter>
          ariaLabel={t("levelLabel")}
          value={level}
          onChange={setLevel}
          options={[
            { value: "all", label: t("withCount", { label: t("all"), count: high + medium }) },
            { value: "high", label: t("withCount", { label: t("level.high"), count: high }) },
            { value: "medium", label: t("withCount", { label: t("level.medium"), count: medium }) },
          ]}
        />
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {t("intro")}
        </p>

        {list.isPending ? (
          <StatusText tone="muted">{t("loading")}</StatusText>
        ) : list.isError ? (
          <StatusText tone="error">{errorText(list.error)}</StatusText>
        ) : list.data.members.length === 0 ? (
          <p className="rounded-[1.6rem] px-4 py-6 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
            {t("empty")}
          </p>
        ) : (
          <div
            className="divide-y rounded-[1.6rem] px-4"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", borderColor: "var(--border)" }}
            data-testid="risk-list"
          >
            {list.data.members.map((member) => (
              <AtRiskRow key={member.user_id} member={member} onOpen={setOpen} />
            ))}
          </div>
        )}

        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {t("winBackNote")}{" "}
          <Link href={adminHref("/admin/metrics?tab=automations", slug)} className="font-semibold" style={{ color: "var(--primary)" }}>
            {t("automationsLink")}
          </Link>
        </p>
      </div>
      {open ? <RiskPanel userId={open} onClose={() => setOpen(null)} /> : null}
    </main>
  );
}

/** One member's reasons and «Ιστορικό ενεργειών»: who did what and when. */
function RiskPanel({ userId, onClose }: { userId: string; onClose: () => void }) {
  const t = useTranslations("AtRisk");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const errorText = useLeadErrorText();
  const time = useGymTime();
  const detail = useQuery({
    queryKey: atRiskMemberKey(userId),
    enabled: Boolean(token),
    queryFn: () => fetchMemberAtRisk(token!, userId),
  });
  const member = detail.data?.member;
  const name = personName(member?.person) ?? t("unknownMember");

  return (
    <SidePanel title={member ? name : t("title")} subtitle={t("title")} onClose={onClose}>
      {detail.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : detail.isError || !member ? (
        <StatusText tone="error">{errorText(detail.error)}</StatusText>
      ) : (
        <div className="space-y-6" data-testid="risk-panel">
          <section className="space-y-2">
            <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {t("why")}
            </h3>
            <ul className="space-y-1">
              {sortedReasons(member).map((reason) => {
                const line = reasonLine(reason);
                return (
                  <li key={reason.code} className="text-sm" style={{ color: "var(--text-soft)" }}>
                    {t(`reason.${line.key}`, line.values)}
                  </li>
                );
              })}
            </ul>
            {member.suggested_action !== "none" ? (
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {t(`action.${member.suggested_action}`)}
              </p>
            ) : null}
            <p className="text-xs" style={{ color: "var(--muted)" }}>
              {t("since", { when: time.format(member.level_since, "day") })}
            </p>
          </section>

          <section className="space-y-2">
            <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {t("history")}
            </h3>
            {detail.data.actions.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                {t("historyEmpty")}
              </p>
            ) : (
              <ol className="space-y-2" data-testid="risk-history">
                {detail.data.actions.map((action) => (
                  <li key={action.id} className="rounded-2xl px-3 py-2.5" style={{ background: "var(--panel-muted)" }}>
                    <p className="text-sm" style={{ color: "var(--text)" }}>
                      {action.kind === "contacted"
                        ? t("log.contacted", { channel: t(`channel.${action.channel ?? "phone"}`) })
                        : action.kind === "snoozed" && action.snoozed_until
                          ? t("log.snoozed", { until: time.format(`${action.snoozed_until}T12:00:00Z`, "day") })
                          : t("log.unsnoozed")}
                    </p>
                    <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
                      {t("byWhoWhen", { name: personName(action.actor) ?? t("formerStaff"), when: time.format(action.at) })}
                    </p>
                  </li>
                ))}
              </ol>
            )}
          </section>

          <Link
            href={adminHref(`/admin/users/${member.user_id}`, slug)}
            className="inline-flex text-sm font-semibold"
            style={{ color: "var(--primary)" }}
          >
            {t("openProfile")}
          </Link>
        </div>
      )}
    </SidePanel>
  );
}
