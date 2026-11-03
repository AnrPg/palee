"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { coachPayKeys, fetchPayRules, type PayRule } from "@/api/coach-pay";
import { useStaffCoaches } from "@/components/admin/finance/packages/use-package-authoring";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { activeRules, payPeople, ruleSentence, type PayPerson } from "./coach-pay";
import { PayRuleForm } from "./PayRuleForm";
import { Initials, NetMark, useGymToday, usePercent, useShortDate } from "./pay-ui";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * Οικονομικά › Αμοιβές coaches › Κανόνες (mockup W1 s4, option A): every
 * person with their rules as sentences; someone without a rule stands out
 * («Χωρίς κανόνα: δεν θα πληρωθεί»). «Προσθήκη κανόνα» and a tap on a rule
 * open the side panel.
 */
export function PayRulesView({ canEdit }: { canEdit: boolean }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const today = useGymToday();
  const staff = useStaffCoaches();
  const [editing, setEditing] = useState<{ person: PayPerson; rule: PayRule | null } | null>(null);

  const query = useQuery({ queryKey: coachPayKeys.rules, enabled: Boolean(token), queryFn: () => fetchPayRules(token) });
  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;

  const people = payPeople(staff, activeRules(query.data?.rules ?? [], today), t("unnamed"));

  return (
    <section className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="pay-rules">
      {people.length === 0 ? <p className="p-5 text-sm" style={{ color: "var(--dim)" }}>{t("noStaff")}</p> : null}
      <ul>
        {people.map((person) => (
          <li key={person.userId} className="flex flex-wrap items-start gap-3 border-b px-4 py-3 last:border-b-0 sm:flex-nowrap" style={{ borderColor: "var(--border)" }} data-testid="pay-person">
            <Initials name={person.name} />
            <div className="min-w-0 flex-1">
              <p className="font-semibold" style={{ color: "var(--text)" }}>{person.name}</p>
              {person.rules.length === 0 ? (
                <p className="text-sm font-medium" style={{ color: "var(--warning)" }} data-testid="pay-person-no-rule">{t("noRule")}</p>
              ) : (
                <ul className="mt-0.5 space-y-0.5">
                  {person.rules.map((rule) => (
                    <li key={rule.id}>
                      <RuleLine rule={rule} onOpen={canEdit ? () => setEditing({ person, rule }) : undefined} />
                    </li>
                  ))}
                </ul>
              )}
            </div>
            {canEdit ? (
              <button
                type="button"
                className="shrink-0 rounded-full px-3 py-1.5 text-sm font-semibold"
                style={{ color: "var(--primary)", border: "1px solid var(--border)" }}
                onClick={() => setEditing({ person, rule: null })}
                data-testid="pay-add-rule"
              >
                {t("addRule")}
              </button>
            ) : null}
          </li>
        ))}
      </ul>
      {editing ? <PayRuleForm userId={editing.person.userId} name={editing.person.name} rule={editing.rule} onClose={() => setEditing(null)} /> : null}
    </section>
  );
}

/** One rule as a sentence; net rules carry the «Καθαρά» mark. */
export function RuleLine({ rule, onOpen }: { rule: PayRule; onOpen?: () => void }) {
  const t = useTranslations("CoachPay");
  const locale = useUiLocale();
  const percent = usePercent();
  const shortDate = useShortDate();
  const sentence = ruleSentence(rule, (cents) => formatMinorUnits(locale, cents, rule.currency), percent);
  const text = (
    <span className="inline-flex flex-wrap items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
      {t(sentence.key, sentence.values)}
      {rule.ends_on ? <span style={{ color: "var(--dim)" }}>{t("ruleUntil", { date: shortDate(rule.ends_on) })}</span> : null}
      {rule.amount_basis === "net" ? <NetMark /> : null}
    </span>
  );
  if (!onOpen) return text;
  return (
    <button type="button" className="text-start hover:underline" onClick={onOpen} data-testid="pay-rule-line">
      {text}
    </button>
  );
}
