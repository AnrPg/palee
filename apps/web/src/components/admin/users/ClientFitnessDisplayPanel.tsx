"use client";

import type { ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { clientFitnessDisplayKey, fetchClientFitnessDisplay, saveClientFitnessDisplay } from "@/api/staff";
import {
  clientChoiceWins,
  clientOwnDisplay,
  coachChoice,
  overrideFor,
  personalFacts,
  type CoachFitnessChoice,
} from "@/components/admin/users/client-fitness-display";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { ChangedMark } from "@/components/ui/ChangedMark";
import { useDraftForm } from "@/components/ui/DraftForms";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-395: the coach's side of a client's «Επίπεδο φυσικής κατάστασης».
 * The client's body weight and birth year (read-only, personal: the API
 * answers only a coach with an active coaching relationship) and what the
 * client's card shows: their own choice, «Μόνο πρόοδος» or «Τίποτα». A
 * stricter coach choice shows on the card as «Το όρισε ο coach σου».
 * Saved with the profile's «Αποθήκευση» bar (ADR-276). A staff member who
 * does not coach the client (403 not_your_client) sees no panel at all.
 */
export function ClientFitnessDisplayPanel({
  userId,
  nickname,
  frame,
}: {
  userId: string;
  nickname: string;
  frame: (content: ReactNode) => ReactNode;
}) {
  const t = useTranslations("FitnessCoach");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const key = clientFitnessDisplayKey(userId);
  const view = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchClientFitnessDisplay(token!, userId),
    retry: false,
  });
  const form = useDraftForm<{ choice: CoachFitnessChoice }>({
    server: { choice: coachChoice(view.data) },
    testId: "client-fitness-display-save-bar",
    save: async (draft) => {
      const saved = await saveClientFitnessDisplay(token!, userId, overrideFor(draft.choice));
      queryClient.setQueryData(key, saved);
    },
    describeError: (error) => localizeError(error, i18n),
  });

  if (view.error instanceof ApiError && view.error.status === 403) return null;
  if (view.isError) return frame(<StatusText tone="error">{localizeError(view.error, i18n)}</StatusText>);
  if (!view.data) return null;

  const facts = personalFacts(view.data);
  const own = clientOwnDisplay(view.data);
  const choice = form.draft.choice;
  const missing = t("notFilled");

  return frame(
    <div className="space-y-4" data-testid="client-fitness-display">
      {facts ? (
        <dl className="grid grid-cols-2 gap-3 text-sm" data-testid="client-fitness-facts">
          <div>
            <dt className="text-xs" style={{ color: "var(--dim)" }}>{t("bodyWeight")}</dt>
            <dd className="font-semibold" style={{ color: facts.weightKg === null ? "var(--muted)" : "var(--text)" }}>
              {facts.weightKg === null ? missing : t("kg", { weight: format.number(facts.weightKg, { maximumFractionDigits: 1 }) })}
            </dd>
          </div>
          <div>
            <dt className="text-xs" style={{ color: "var(--dim)" }}>{t("birthYear")}</dt>
            <dd className="font-semibold" style={{ color: facts.birthYear === null ? "var(--muted)" : "var(--text)" }}>
              {facts.birthYear === null ? missing : String(facts.birthYear)}
            </dd>
          </div>
        </dl>
      ) : (
        <p className="text-sm" style={{ color: "var(--muted)" }} data-testid="client-fitness-facts">
          {t("noneFilled", { name: nickname })}
        </p>
      )}

      <div className="space-y-1.5">
        <div className="flex items-center gap-2">
          <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("question")}</p>
          {form.changed.has("choice") ? <ChangedMark /> : null}
        </div>
        <SegmentPicker<CoachFitnessChoice>
          ariaLabel={t("question")}
          semantics="radiogroup"
          value={choice}
          onChange={(next) => form.edit({ choice: next })}
          options={[
            { value: "client", label: t("theirChoice", { choice: t(`display_${own}`) }), disabled: form.saving },
            { value: "progress_only", label: t("display_progress_only"), disabled: form.saving },
            { value: "none", label: t("display_none"), disabled: form.saving },
          ]}
        />
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("hint")}</p>
        {clientChoiceWins(view.data, choice) ? (
          <p className="text-xs" style={{ color: "var(--muted)" }} data-testid="client-fitness-stricter">
            {t("theirsIsStricter", { name: nickname, choice: t(`display_${own}`) })}
          </p>
        ) : null}
      </div>

      {form.bar}
    </div>,
  );
}
