"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { RankStanding } from "@/api/body-devices";
import { safeVideoUrl } from "@/components/client/video";
import { HubCard } from "@/components/member-app/HubParts";
import { rankCriteria, skillTicks } from "@/lib/body-devices";

/**
 * «Επόμενος βαθμός» (mockup «Η πρόοδός μου», option Α; kept as one small
 * component so another option can replace it): a ring with the skills done,
 * the days and classes the ladder counts, «Σου μένουν» first and what is
 * done collapsed. Calm: only the person's own progress, never others'.
 */
export function NextRankCard({ standing }: { standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const [showDone, setShowDone] = useState(false);
  const next = standing.next;
  const progress = standing.progress;
  if (!next) return null;
  const criteria = rankCriteria(standing);
  const ticks = skillTicks(standing);
  const left = ticks.filter((tick) => !tick.checked);
  const done = ticks.filter((tick) => tick.checked);
  const counts = [
    criteria.includes("days") && typeof progress?.days?.needed === "number"
      ? t("ranks.my.days", { done: progress.days.done ?? 0, needed: progress.days.needed })
      : null,
    criteria.includes("classes") && typeof progress?.classes?.needed === "number"
      ? t("ranks.my.classes", { done: progress.classes.done ?? 0, needed: progress.classes.needed })
      : null,
    ticks.length > 0 ? t("ranks.skillsDone", { done: done.length, total: ticks.length }) : null,
  ].filter(Boolean);

  return (
    <HubCard>
      <div className="flex flex-col gap-3" data-testid="next-rank-card">
        <div className="flex items-center gap-4">
          {ticks.length > 0 ? <Ring done={done.length} total={ticks.length} /> : null}
          <div className="flex min-w-0 flex-col">
            <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("ranks.my.nextRank")}</span>
            <span className="text-lg font-bold" style={{ color: "var(--text)" }}>{next.name}</span>
            {counts.length > 0 ? <span className="text-sm" style={{ color: "var(--text-soft)" }}>{counts.join(" · ")}</span> : null}
          </div>
        </div>
        {left.length > 0 ? (
          <div className="flex flex-col gap-2">
            <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("ranks.my.left")}</span>
            <ul className="flex flex-col gap-2">
              {left.map((tick) => (
                <li key={tick.id ?? tick.name} className="flex gap-2">
                  <span aria-hidden="true" className="mt-1 h-3 w-3 shrink-0 rounded-full" style={{ border: "1px solid var(--border)" }} />
                  <SkillWithExtras name={tick.name} note={tick.note} video={tick.video} />
                </li>
              ))}
            </ul>
          </div>
        ) : null}
        {done.length > 0 ? (
          <div className="flex flex-col gap-1">
            <button type="button" aria-expanded={showDone} onClick={() => setShowDone(!showDone)} className="self-start text-start text-sm" style={{ color: "var(--text-soft)" }}>
              <span className="font-semibold">{t("ranks.my.have")}</span>{" "}
              {showDone ? null : <span>{done.map((tick) => tick.name).join(" · ")}</span>}
            </button>
            {showDone ? (
              <ul className="flex flex-col gap-2">
                {done.map((tick) => (
                  <li key={tick.id ?? tick.name} className="flex gap-2">
                    <span aria-hidden="true" className="mt-0.5 text-xs font-bold" style={{ color: "var(--success)" }}>✓</span>
                    <SkillWithExtras name={tick.name} note={tick.note} video={tick.video} />
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        ) : null}
      </div>
    </HubCard>
  );
}

/** «3/5» in a ring of the skills done. */
function Ring({ done, total }: { done: number; total: number }) {
  const t = useTranslations("BodyDevices");
  const radius = 26;
  const length = 2 * Math.PI * radius;
  const share = total > 0 ? done / total : 0;
  return (
    <svg viewBox="0 0 64 64" className="h-16 w-16 shrink-0" role="img" aria-label={t("ranks.skillsDone", { done, total })}>
      <circle cx="32" cy="32" r={radius} fill="none" stroke="var(--panel-muted)" strokeWidth="6" />
      <circle
        cx="32"
        cy="32"
        r={radius}
        fill="none"
        stroke="var(--success)"
        strokeWidth="6"
        strokeLinecap="round"
        strokeDasharray={`${share * length} ${length}`}
        className="origin-center -rotate-90 [transform-box:fill-box]"
      />
      <text x="32" y="36" textAnchor="middle" fontSize="13" fontWeight="700" fill="var(--text)">
        {done}/{total}
      </text>
    </svg>
  );
}

/** A skill, with the coach's note and video collapsed under it when there are any. */
export function SkillWithExtras({ name, note, video }: { name: string; note: string | null; video: string | null }) {
  const t = useTranslations("BodyDevices");
  const link = safeVideoUrl(video);
  return (
    <div className="flex flex-col gap-1">
      <span className="text-sm" style={{ color: "var(--text)" }}>{name}</span>
      {note ? (
        <details className="text-xs" style={{ color: "var(--text-soft)" }}>
          <summary className="cursor-pointer font-semibold">{t("ranks.my.note")}</summary>
          <p className="whitespace-pre-wrap pt-1" data-user-text>{note}</p>
        </details>
      ) : null}
      {link ? (
        <details className="text-xs" style={{ color: "var(--text-soft)" }}>
          <summary className="cursor-pointer font-semibold">{t("ranks.my.video")}</summary>
          <a href={link} target="_blank" rel="noopener noreferrer" className="block pt-1 font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("ranks.my.openVideo")}
          </a>
        </details>
      ) : null}
    </div>
  );
}
