"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchPaleeConsent,
  paleeConsentKey,
  putPaleeConsent,
  withdrawPaleeConsent,
  type PaleeChoice,
} from "@/api/training-floor";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * ADR-394: «Όλο το Palee» in «Κοινοποίηση και ορατότητα». The switch is the
 * same answer the board asks once: on, others see nickname, box and score;
 * off, only the person sees their place. «Έξοδος» withdraws the answer: they
 * leave every Palee-wide board at once and are asked again next time.
 */
export function PaleeLeaderboardSetting() {
  const t = useTranslations("TrainingFloor");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const consent = useQuery({
    queryKey: paleeConsentKey,
    enabled: Boolean(token),
    queryFn: () => fetchPaleeConsent(token!),
  });
  const save = useMutation({
    mutationFn: (choice: PaleeChoice | null) => (choice ? putPaleeConsent(token!, choice) : withdrawPaleeConsent(token!)),
    onSuccess: (data) => {
      queryClient.setQueryData(paleeConsentKey, data);
      void queryClient.invalidateQueries({ queryKey: ["training-floor", "leaderboard"] });
    },
  });

  const choice = consent.data?.choice ?? null;

  return (
    <div id="palee-leaderboard" className="space-y-2" data-testid="palee-leaderboard-setting">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("paleeSettingTitle")}</p>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("paleeSettingHint")}</p>
      <Switch
        label={t("paleeSettingShare")}
        hint={t("paleeSettingShareHint")}
        checked={choice === "share"}
        disabled={!consent.data || save.isPending}
        onChange={(on) => save.mutate(on ? "share" : "see_only")}
      />
      {consent.data && choice === null ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("paleeSettingNotAsked")}</p>
      ) : null}
      {choice !== null ? (
        <button
          type="button"
          disabled={save.isPending}
          onClick={() => save.mutate(null)}
          className="text-sm font-semibold underline disabled:opacity-50"
          style={{ color: "var(--primary)" }}
        >
          {t("paleeSettingWithdraw")}
        </button>
      ) : null}
      {save.isError ? <ErrorNotice variant="field">{t("paleeSettingFailed")}</ErrorNotice> : null}
    </div>
  );
}
