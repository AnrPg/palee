"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useMemo } from "react";

import {
  fetchLeaderboardProfile,
  leaderboardProfileKey,
  updateLeaderboardProfile,
  type LeaderboardProfile,
  type LeaderboardProfileRequest,
} from "@/api/training-floor";
import { LoadingLine } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { birthYearOptions } from "@/lib/training-floor";

const fieldClass = "mt-1 w-full rounded-xl px-3 py-2 text-sm";
const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * ADR-356: what the person tells the box so WOD results are compared fairly,
 * both optional and only while they are on the leaderboard. Each choice saves
 * on its own, like the other sharing switches.
 */
export function LeaderboardProfileFields({ slug }: { slug: string }) {
  const t = useTranslations("TrainingFloor");
  const id = useId();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = leaderboardProfileKey(slug);
  const profile = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchLeaderboardProfile(token!, slug),
  });
  const save = useMutation({
    mutationFn: (change: LeaderboardProfileRequest) => updateLeaderboardProfile(token!, slug, change),
    onSuccess: (data) => {
      queryClient.setQueryData<LeaderboardProfile>(key, data);
      void queryClient.invalidateQueries({ queryKey: ["training-floor", "leaderboard"] });
    },
  });
  const years = useMemo(() => birthYearOptions(new Date().getFullYear()), []);

  if (profile.isPending) return <LoadingLine />;
  if (!profile.data?.opted_in) return null;
  const current = save.isPending ? { ...profile.data, ...save.variables } : profile.data;
  const change = (next: LeaderboardProfileRequest) =>
    save.mutate({ division: current.division ?? null, birth_year: current.birth_year ?? null, ...next });

  return (
    <div className="space-y-3" data-testid="leaderboard-profile">
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("profileHint")}</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <label htmlFor={`${id}-division`} className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {t("profileDivision")}
          <Select
            id={`${id}-division`}
            className={fieldClass}
            style={fieldStyle}
            value={current.division ?? ""}
            disabled={save.isPending}
            onValueChange={(value) => change({ division: value === "women" || value === "men" ? value : null })}
          >
            <option value="">{t("profileNotSaid")}</option>
            <option value="women">{t("division_women")}</option>
            <option value="men">{t("division_men")}</option>
          </Select>
        </label>
        <label htmlFor={`${id}-year`} className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {t("profileBirthYear")}
          <Select
            id={`${id}-year`}
            className={fieldClass}
            style={fieldStyle}
            value={current.birth_year ? String(current.birth_year) : ""}
            disabled={save.isPending}
            onValueChange={(value) => change({ birth_year: value ? Number(value) : null })}
          >
            <option value="">{t("profileNotSaid")}</option>
            {years.map((year) => (
              <option key={year} value={String(year)}>
                {year}
              </option>
            ))}
          </Select>
        </label>
      </div>
      {save.isError ? <ErrorNotice>{t("profileSaveError")}</ErrorNotice> : null}
    </div>
  );
}
