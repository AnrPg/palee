"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  AT_RISK_KEY,
  atRiskMemberKey,
  CONTACT_CHANNELS,
  markMemberContacted,
  snoozeMember,
  type ContactChannel,
  type MemberRisk,
} from "@/api/leads";
import { LeadAvatar, useGymTime, useLeadErrorText } from "@/components/admin/leads/leads-ui";
import { useSession } from "@/components/session-provider";
import { Pill, StatusText } from "@/components/staff/staff-ui";

import { ChoiceButton } from "./ChoiceButton";
import { contactedThisSpell, personName, reasonLine, SNOOZE_DAYS, sortedReasons } from "./risk-model";

const outlined = { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" };
const ghost = { background: "transparent", color: "var(--text-soft)" };

/**
 * One member «Σε κίνδυνο» (W2 p4 A): the level, «Γιατί» in plain words,
 * what to do, «Επικοινώνησα» (who and when once done, ADR-384) and
 * «Αργότερα». No score is shown (ADR-347).
 */
export function AtRiskRow({ member, onOpen, compact = false }: { member: MemberRisk; onOpen: (userId: string) => void; compact?: boolean }) {
  const t = useTranslations("AtRisk");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const time = useGymTime();
  const name = personName(member.person) ?? t("unknownMember");

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: AT_RISK_KEY });
    void queryClient.invalidateQueries({ queryKey: atRiskMemberKey(member.user_id) });
  };
  const contacted = useMutation({
    mutationFn: (channel: ContactChannel) => markMemberContacted(token!, member.user_id, channel),
    onSuccess: refresh,
  });
  const snooze = useMutation({
    mutationFn: (days: number) => snoozeMember(token!, member.user_id, days),
    onSuccess: refresh,
  });

  const done = contactedThisSpell(member);
  const by = personName(member.contacted_by);
  const reasons = sortedReasons(member);

  return (
    <div className="flex flex-col gap-3 py-4 sm:flex-row sm:items-start" data-testid={`risk-row-${member.user_id}`}>
      <button type="button" onClick={() => onOpen(member.user_id)} className="flex min-w-0 flex-1 items-start gap-3 text-start">
        <LeadAvatar name={name} />
        <span className="min-w-0 space-y-1">
          <span className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {name}
            </span>
            <Pill tone={member.level === "high" ? "danger" : "warning"}>{t(`level.${member.level}`)}</Pill>
          </span>
          <span className="block space-y-0.5">
            {(compact ? reasons.slice(0, 2) : reasons).map((reason) => {
              const line = reasonLine(reason);
              return (
                <span key={reason.code} className="block text-xs" style={{ color: "var(--muted)" }}>
                  {t(`reason.${line.key}`, line.values)}
                </span>
              );
            })}
          </span>
          {member.suggested_action !== "none" ? (
            <span className="block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {t(`action.${member.suggested_action}`)}
            </span>
          ) : null}
        </span>
      </button>
      <div className="flex shrink-0 flex-wrap items-center gap-2 sm:justify-end">
        {done ? (
          <Pill tone="success">
            {by ? t("contactedBy", { name: by, when: time.format(member.contacted_at!) }) : t("contactedAt", { when: time.format(member.contacted_at!) })}
          </Pill>
        ) : (
          <ChoiceButton<ContactChannel>
            label={t("contacted")}
            style={outlined}
            disabled={contacted.isPending}
            testId={`risk-contacted-${member.user_id}`}
            onPick={(channel) => contacted.mutate(channel)}
            choices={CONTACT_CHANNELS.map((value) => ({ value, label: t(`channel.${value}`) }))}
          />
        )}
        <ChoiceButton<number>
          label={t("later")}
          style={ghost}
          disabled={snooze.isPending}
          testId={`risk-later-${member.user_id}`}
          onPick={(days) => snooze.mutate(days)}
          choices={SNOOZE_DAYS.map((days) => ({ value: days, label: t("laterDays", { days }) }))}
        />
      </div>
      {contacted.isError || snooze.isError ? (
        <StatusText tone="error">{errorText(contacted.error ?? snooze.error)}</StatusText>
      ) : null}
    </div>
  );
}
