"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  awardRank,
  clientRanksKey,
  fetchClientDiploma,
  fetchClientRanks,
  revokeRankAward,
  type RankStanding,
} from "@/api/body-devices";
import { Belt } from "@/components/body-devices/Belt";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { promotionChoices, rankProgress } from "@/lib/body-devices";
import { saveFile } from "@/components/admin/coach-pay/pay-ui";
import { formatRankDate, todayIso } from "@/components/body-devices/rank-dates";

/**
 * «Βαθμός» in a client's profile (ADR-377, mockup e2coach A): where the
 * person stands on each of the box's ladders, what is missing for the next
 * rank, and «Προαγωγή». Always the coach's decision: «Έτοιμος» only informs.
 * A rank is never lowered; an award is withdrawn with a reason.
 */
export function ClientRanks({
  token,
  slug,
  userId,
  nickname,
  frame,
}: {
  token: string;
  slug: string;
  userId: string;
  nickname: string;
  frame: (content: ReactNode) => ReactNode;
}) {
  const standings = useQuery({
    queryKey: clientRanksKey(slug, userId),
    enabled: Boolean(token && slug),
    queryFn: () => fetchClientRanks(token, slug, userId),
    retry: false,
  });
  if (!standings.data || standings.data.ladders.length === 0) return null;
  return (
    <>
      {frame(
        <div className="flex flex-col gap-3" data-testid="client-ranks">
          {standings.data.ladders.map((standing) => (
            <StandingCard key={standing.ladder.id} token={token} slug={slug} userId={userId} nickname={nickname} standing={standing} />
          ))}
        </div>,
      )}
    </>
  );
}

function StandingCard({ token, slug, userId, nickname, standing }: { token: string; slug: string; userId: string; nickname: string; standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const [promoting, setPromoting] = useState(false);
  const [withdrawing, setWithdrawing] = useState(false);
  const current = standing.current;
  const progress = rankProgress(standing);
  const diploma = useMutation({
    mutationFn: (awardId: string) => fetchClientDiploma(token, slug, awardId),
    onSuccess: (blob, awardId) => saveFile(blob, `${awardId}.pdf`),
  });

  return (
    <section className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-center justify-between gap-3">
        <b className="text-sm" style={{ color: "var(--text)" }}>{standing.ladder.name}</b>
        {current ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("ranks.since", { date: formatRankDate(current.awarded_on, locale) })}</span> : null}
      </div>
      {current ? (
        <>
          <Belt color={current.rank.color} stripes={current.stripes} label={current.rank.name} />
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {t("ranks.currentLine", { rank: current.rank.name, stripes: current.stripes })}
            {standing.next ? ` · ${t("ranks.nextIs", { rank: standing.next.name })}` : ""}
          </p>
        </>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ranks.noRankYet")}</p>
      )}
      {standing.progress ? <ProgressLines standing={standing} /> : null}
      {progress !== null ? (
        <div className="h-1.5 rounded-full" style={{ background: "var(--panel-muted)" }} aria-hidden="true">
          <div className="h-full rounded-full" style={{ width: `${Math.round(progress * 100)}%`, background: "var(--primary)" }} />
        </div>
      ) : null}
      {standing.progress?.ready ? (
        <p className="text-xs font-semibold" style={{ color: "var(--success)" }}>{t("ranks.ready")}</p>
      ) : null}
      <div className="flex flex-wrap items-center gap-3">
        {promotionChoices(standing).length > 0 ? (
          <button
            type="button"
            onClick={() => setPromoting(true)}
            className="min-h-11 rounded-2xl px-5 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("ranks.promote")}
          </button>
        ) : null}
        {current ? (
          <button type="button" onClick={() => diploma.mutate(current.award_id)} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("ranks.diploma")}
          </button>
        ) : null}
        {current ? (
          <button type="button" onClick={() => setWithdrawing(true)} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {t("ranks.withdraw")}
          </button>
        ) : null}
      </div>
      {diploma.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      {promoting ? (
        <PromoteSheet token={token} slug={slug} userId={userId} nickname={nickname} standing={standing} onClose={() => setPromoting(false)} />
      ) : null}
      {withdrawing && current ? (
        <WithdrawSheet token={token} slug={slug} userId={userId} awardId={current.award_id} rank={current.rank.name} onClose={() => setWithdrawing(false)} />
      ) : null}
    </section>
  );
}

export function ProgressLines({ standing }: { standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const progress = standing.progress;
  if (!progress) return null;
  const parts: string[] = [];
  if (typeof progress.classes.needed === "number") parts.push(t("ranks.classesCount", { done: progress.classes.done ?? 0, needed: progress.classes.needed }));
  if (typeof progress.days.needed === "number") parts.push(t("ranks.daysCount", { done: progress.days.done ?? 0, needed: progress.days.needed }));
  if (progress.skills.length > 0) parts.push(progress.skills.join(", "));
  if (parts.length === 0) return null;
  return <p className="text-xs" style={{ color: "var(--text-soft)" }}>{parts.join(" · ")}</p>;
}

function PromoteSheet({
  token,
  slug,
  userId,
  nickname,
  standing,
  onClose,
}: {
  token: string;
  slug: string;
  userId: string;
  nickname: string;
  standing: RankStanding;
  onClose: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const queryClient = useQueryClient();
  const choices = promotionChoices(standing);
  const [choice, setChoice] = useState(0);
  const [date, setDate] = useState(todayIso());
  const [note, setNote] = useState("");
  const skillsForNext = standing.next?.requirements.skills ?? [];
  const [skills, setSkills] = useState<string[]>([]);
  const picked = choices[choice];
  const award = useMutation({
    mutationFn: () =>
      awardRank(token, slug, userId, {
        ladder_id: standing.ladder.id,
        rank_id: picked.rank.id,
        stripes: picked.stripes,
        awarded_on: date,
        ...(note.trim() ? { note: note.trim() } : {}),
        ...(skills.length ? { skills_checked: skills } : {}),
      }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: clientRanksKey(slug, userId) });
      onClose();
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={t("ranks.promote")}
      description={`${nickname} · ${standing.ladder.name}`}
      titleId={`promote-${standing.ladder.id}`}
      variant="sheet"
      size="md"
      testId="promote-sheet"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <button type="button" onClick={onClose} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button
            type="button"
            disabled={award.isPending || !picked}
            onClick={() => award.mutate()}
            className="min-h-11 rounded-2xl px-5 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("ranks.promote")}
          </button>
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap gap-2" role="group" aria-label={t("ranks.promote")}>
          {choices.map((option, index) => (
            <button
              key={`${option.kind}-${option.rank.id}`}
              type="button"
              aria-pressed={choice === index}
              onClick={() => setChoice(index)}
              className="flex min-h-11 items-center gap-2 rounded-full px-3 text-sm font-semibold"
              style={{
                background: choice === index ? "var(--primary)" : "var(--panel-muted)",
                color: choice === index ? "var(--primary-contrast)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              <Belt color={option.rank.color} stripes={option.stripes} className="h-3 w-10" />
              {option.kind === "stripe" ? t("ranks.plusStripe", { stripes: option.stripes }) : option.rank.name}
            </button>
          ))}
        </div>
        {picked?.kind === "rank" && skillsForNext.length > 0 ? (
          <div className="flex flex-col gap-1">
            <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("ranks.skillsFor", { rank: picked.rank.name })}</span>
            <div className="flex flex-wrap gap-2">
              {skillsForNext.map((skill) => {
                const on = skills.includes(skill);
                return (
                  <button
                    key={skill}
                    type="button"
                    aria-pressed={on}
                    onClick={() => setSkills(on ? skills.filter((entry) => entry !== skill) : [...skills, skill])}
                    className="min-h-9 rounded-full px-3 text-sm"
                    style={{ background: on ? "var(--panel-raised)" : "var(--panel-muted)", border: `1px solid ${on ? "var(--success)" : "var(--border)"}`, color: "var(--text)" }}
                  >
                    {on ? `✓ ${skill}` : skill}
                  </button>
                );
              })}
            </div>
          </div>
        ) : null}
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ranks.date")}
          <DateInput value={date} onValueChange={(value) => setDate(value || todayIso())} />
        </label>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ranks.note")}
          <input
            value={note}
            maxLength={500}
            onChange={(event) => setNote(event.target.value)}
            className="min-h-11 rounded-2xl px-4"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("ranks.promoteHint")}</p>
        {award.isError ? <ErrorNotice>{t("ranks.promoteFailed")}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}

function WithdrawSheet({
  token,
  slug,
  userId,
  awardId,
  rank,
  onClose,
}: {
  token: string;
  slug: string;
  userId: string;
  awardId: string;
  rank: string;
  onClose: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const queryClient = useQueryClient();
  const [reason, setReason] = useState("");
  const [reasonError, setReasonError] = useState(false);
  const revoke = useMutation({
    mutationFn: () => revokeRankAward(token, slug, awardId, reason.trim()),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: clientRanksKey(slug, userId) });
      onClose();
    },
  });
  return (
    <Dialog
      onClose={onClose}
      title={t("ranks.withdrawTitle", { rank })}
      titleId={`withdraw-${awardId}`}
      variant="sheet"
      size="sm"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <button type="button" onClick={onClose} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button
            type="button"
            disabled={revoke.isPending}
            onClick={() => {
              if (reason.trim().length < 2) {
                setReasonError(true);
                return;
              }
              revoke.mutate();
            }}
            className="min-h-11 rounded-2xl px-5 text-sm font-bold"
            style={{ background: "var(--danger)", color: "var(--primary-contrast)" }}
          >
            {t("ranks.withdraw")}
          </button>
        </div>
      }
    >
      <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("ranks.withdrawReason")}
        <input
          value={reason}
          maxLength={280}
          aria-invalid={reasonError}
          onChange={(event) => {
            setReason(event.target.value);
            setReasonError(false);
          }}
          className="min-h-11 rounded-2xl px-4"
          style={{ background: "var(--panel-muted)", border: `1px solid ${reasonError ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
        />
        {reasonError ? <span className="text-xs font-normal" style={{ color: "var(--danger)" }}>{t("ranks.withdrawReasonRequired")}</span> : null}
      </label>
      {revoke.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
    </Dialog>
  );
}
