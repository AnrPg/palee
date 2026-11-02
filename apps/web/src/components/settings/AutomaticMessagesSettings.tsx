"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  fetchMyAutomaticMessages,
  MY_AUTOMATIC_MESSAGES_KEY,
  updateMyAutomaticMessages,
  type AutomaticMessages,
  type AutomaticMessagesUpdate,
} from "@/api/leads";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { clientRole } from "@/lib/role-navigation";

const MONTHS = Array.from({ length: 12 }, (_, index) => index + 1);
const DAYS = Array.from({ length: 31 }, (_, index) => index + 1);

/**
 * Εγώ › Ρυθμίσεις › «Αυτόματα μηνύματα» (ADR-346, W2 p5 A): one switch for
 * every automatic message of the member's box, the birthday as day and month
 * only, and the per-message switches under «Προχωρημένα». Shown to box
 * members only; important notices (payments, cancellations) always arrive.
 */
export function AutomaticMessagesSettings() {
  const { membership } = useSelectedMembershipRole();
  if (!clientRole(membership)) return null;
  const boxName =
    (membership as { organization?: { name?: string } } | null | undefined)?.organization?.name ?? null;
  return <Settings boxName={boxName} />;
}

function Settings({ boxName }: { boxName: string | null }) {
  const t = useTranslations("AutoMessages");
  const tRecipes = useTranslations("Automations");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [advanced, setAdvanced] = useState(false);

  const prefs = useQuery({
    queryKey: MY_AUTOMATIC_MESSAGES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchMyAutomaticMessages(token!),
  });
  const save = useMutation({
    mutationFn: (body: AutomaticMessagesUpdate) => updateMyAutomaticMessages(token!, body),
    onSuccess: (data) => queryClient.setQueryData<AutomaticMessages>(MY_AUTOMATIC_MESSAGES_KEY, data),
  });

  const monthName = (month: number) => new Intl.DateTimeFormat(locale, { month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(2024, month - 1, 1)));

  return (
    <CollapsibleSection
      id="automatic-messages"
      title={t("title")}
      description={boxName ? t("descriptionBox", { box: boxName }) : t("description")}
    >
      {prefs.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : prefs.isError ? (
        <StatusText tone="error">{localizeError(prefs.error, ui)}</StatusText>
      ) : (
        <div className="space-y-5" data-testid="automatic-messages">
          <Switch
            checked={!prefs.data.opted_out}
            disabled={save.isPending}
            label={t("allLabel")}
            hint={t("allHint")}
            onChange={(on) => save.mutate({ opted_out: !on })}
          />

          {prefs.data.opted_out ? null : (
            <>
              <div className="space-y-2">
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {t("birthday")}
                </p>
                <p className="text-xs" style={{ color: "var(--dim)" }}>
                  {t("birthdayHint")}
                </p>
                <Birthday
                  value={prefs.data.birthday}
                  monthName={monthName}
                  disabled={save.isPending}
                  onChange={(birthday) => save.mutate({ birthday })}
                />
              </div>

              <button
                type="button"
                aria-expanded={advanced}
                onClick={() => setAdvanced((value) => !value)}
                className="text-sm font-semibold"
                style={{ color: "var(--primary)" }}
              >
                {t("advanced")}
              </button>
              {advanced ? (
                <div className="space-y-1">
                  {prefs.data.recipes.map((recipe) => {
                    const off = prefs.data.opted_out_recipes.includes(recipe.key);
                    return (
                      <Switch
                        key={recipe.key}
                        checked={!off}
                        disabled={save.isPending}
                        label={tRecipes.has(`recipe.${recipe.key}`) ? tRecipes(`recipe.${recipe.key}`) : recipe.key}
                        onChange={(on) =>
                          save.mutate({
                            opted_out_recipes: on
                              ? prefs.data.opted_out_recipes.filter((key) => key !== recipe.key)
                              : [...prefs.data.opted_out_recipes, recipe.key],
                          } as AutomaticMessagesUpdate)
                        }
                      />
                    );
                  })}
                </div>
              ) : null}
            </>
          )}
          {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
        </div>
      )}
    </CollapsibleSection>
  );
}

function Birthday({
  value,
  monthName,
  disabled,
  onChange,
}: {
  value: AutomaticMessages["birthday"];
  monthName: (month: number) => string;
  disabled: boolean;
  onChange: (birthday: { day: number; month: number } | null) => void;
}) {
  const t = useTranslations("AutoMessages");
  const [day, setDay] = useState(value ? String(value.day) : "");
  const [month, setMonth] = useState(value ? String(value.month) : "");
  const style = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  function pick(nextDay: string, nextMonth: string) {
    setDay(nextDay);
    setMonth(nextMonth);
    if (nextDay && nextMonth) onChange({ day: Number(nextDay), month: Number(nextMonth) });
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select aria-label={t("day")} value={day} onValueChange={(next) => pick(next, month)} placeholder={t("day")} className="min-h-11 w-24 rounded-xl px-3 text-sm" style={style}>
        {DAYS.map((entry) => (
          <option key={entry} value={String(entry)}>
            {entry}
          </option>
        ))}
      </Select>
      <Select aria-label={t("month")} value={month} onValueChange={(next) => pick(day, next)} placeholder={t("month")} className="min-h-11 flex-1 rounded-xl px-3 text-sm" style={style}>
        {MONTHS.map((entry) => (
          <option key={entry} value={String(entry)}>
            {monthName(entry)}
          </option>
        ))}
      </Select>
      {value ? (
        <button
          type="button"
          disabled={disabled}
          onClick={() => {
            setDay("");
            setMonth("");
            onChange(null);
          }}
          className="text-sm font-semibold"
          style={{ color: "var(--text-soft)" }}
        >
          {t("birthdayClear")}
        </button>
      ) : null}
    </div>
  );
}
