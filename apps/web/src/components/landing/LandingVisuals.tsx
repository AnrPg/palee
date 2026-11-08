"use client";

import type { CSSProperties } from "react";
import { useTranslations } from "next-intl";

/**
 * The small product pictures of the guest landing (ADR-555): drawn with the
 * theme, in the app's own words, so every locale shows the real screens.
 * Each one is decoration next to text that says the same thing. They move
 * on their own (hearts, the drawn line, a booking, a swipe, ticks) and stand
 * still under reduced motion (globals.css, «landing» section).
 */

/** The photo of the sample post (the gym floor is the hero's and the club's). */
export const POST_PHOTO = "/landing-deadlift.jpg";

const card = "rounded-2xl p-4 shadow-sm";
const cardStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" } as const;
const delay = (seconds: number) => ({ animationDelay: `${seconds}s` });

function Avatar({ letter, tone = "var(--primary)" }: { letter: string; tone?: string }) {
  return (
    <span
      aria-hidden="true"
      className="grid size-9 shrink-0 place-items-center rounded-full text-sm font-bold"
      style={{ background: tone, color: "var(--primary-contrast)" }}
    >
      {letter}
    </span>
  );
}

function Heart({ className = "", style }: { className?: string; style?: CSSProperties }) {
  return (
    <svg viewBox="0 0 24 24" className={className} style={style} aria-hidden="true">
      <path
        d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 4.5 6.7 4.5c2.1 0 3.6 1.2 4.3 2.6.7-1.4 2.2-2.6 4.3-2.6 3.7 0 5.8 3.9 4.3 7.3C19.5 16.4 12 21 12 21z"
        fill="var(--heat)"
      />
    </svg>
  );
}

/** A post with its photo: a double-tap heart on the photo, hearts floating up from the kudos. */
export function PostVisual({ photo = POST_PHOTO, withPhoto = true }: { photo?: string; withPhoto?: boolean }) {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} flex flex-col`} style={cardStyle} aria-hidden="true">
      <div className="flex items-center gap-3">
        <Avatar letter={t("demo.post1Name").slice(0, 1)} />
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("demo.post1Name")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.sharePost")}</p>
        </div>
      </div>
      {withPhoto ? (
        <div className="relative mt-3 overflow-hidden rounded-xl">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={photo} alt="" className="landing-kenburns aspect-[16/9] w-full object-cover" />
          <Heart className="landing-heart-pop absolute left-1/2 top-1/2 size-16 drop-shadow-lg" />
        </div>
      ) : null}
      <div className="relative mt-3 flex items-center gap-2">
        <span className="relative inline-flex">
          <Heart className="landing-heart-beat size-5" />
          {[0, 0.9, 1.8].map((start, index) => (
            <Heart key={start} className="landing-float absolute bottom-0 left-0 size-4" style={{ ...delay(start), insetInlineStart: `${index * 6}px` }} />
          ))}
        </span>
        <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("demo.post1Kudos")}</p>
      </div>
    </div>
  );
}

function Meter({ label, value, start }: { label: string; value: number; start: number }) {
  return (
    <div className="grid grid-cols-[5.5rem_1fr] items-center gap-3 text-sm">
      <span style={{ color: "var(--text-soft)" }}>{label}</span>
      <span className="h-2 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }}>
        <span className="landing-fill block h-full rounded-full" style={{ width: `${value}%`, background: "var(--primary)", ...delay(start) }} />
      </span>
    </div>
  );
}

const WEEK = [46, 62, 38, 70, 58, 82, 74];

/** Today's mood, energy and sleep, with the week's mood growing beside it. */
export function JournalVisual({ week = false }: { week?: boolean }) {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} flex flex-col gap-2.5`} style={cardStyle} aria-hidden="true">
      <p className="text-sm font-bold">{t("demo.today")}</p>
      <Meter label={t("tiles.mood")} value={72} start={0} />
      <Meter label={t("tiles.energy")} value={58} start={0.25} />
      <div className="grid grid-cols-[5.5rem_1fr] gap-3 text-sm">
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.sleep")}</span>
        <span className="font-semibold">{t("tiles.sleepValue")}</span>
      </div>
      {week ? (
        <div className="relative min-h-20 flex-1">
          <div className="absolute inset-0 flex items-end gap-1.5 pt-1">
            {WEEK.map((height, index) => (
              <span
                key={index}
                className="landing-grow flex-1 rounded-t-md"
                style={{
                  height: `${height}%`,
                  background: index === WEEK.length - 1 ? "var(--spark)" : "color-mix(in srgb, var(--primary) 70%, transparent)",
                  ...delay(index * 0.12),
                }}
              />
            ))}
          </div>
        </div>
      ) : null}
      <p className="landing-type text-sm italic" style={{ color: "var(--text-soft)" }}>{t("demo.note")}</p>
    </div>
  );
}

/** Ten weeks of a lift climbing, drawn again and again, with the new PR popping out at the end. */
export function ProgressVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} flex flex-col`} style={cardStyle} aria-hidden="true">
      <div className="flex items-baseline justify-between gap-3 text-sm">
        <span className="font-bold">{t("tiles.lift")}</span>
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.weeks")}</span>
      </div>
      <svg viewBox="0 0 300 110" className="mt-2 max-h-56 min-h-24 w-full flex-1 overflow-visible">
        <path d="M8 104 H292" stroke="var(--border)" strokeWidth="1.5" strokeDasharray="4 6" />
        <path
          className="landing-draw"
          pathLength={1}
          d="M8 96 L38 90 L68 92 L98 80 L128 74 L158 76 L188 60 L218 52 L248 40 L284 18"
          fill="none"
          stroke="var(--primary)"
          strokeWidth="5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <circle className="landing-dot" cx="284" cy="18" r="9" fill="var(--spark)" stroke="var(--panel)" strokeWidth="3" />
      </svg>
      <div className="mt-1 flex flex-wrap items-center justify-between gap-2 text-sm">
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.from")}</span>
        <span
          className="landing-badge rounded-full px-2.5 py-1 font-bold"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
        >
          {t("tiles.badge")}
        </span>
      </div>
    </div>
  );
}

/** A training partner suggestion that gets a «yes» and slides away, then the next one comes in. */
export function PartnerVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} landing-swipe flex flex-col justify-center`} style={cardStyle} aria-hidden="true">
      <div className="flex items-center gap-3">
        <Avatar letter={t("tiles.partnerName").slice(0, 1)} tone="var(--heat)" />
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("demo.partnerName")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("demo.partnerMeta")}</p>
        </div>
      </div>
      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--success)" }}>{t("demo.verified")}</p>
      <div className="mt-3 grid grid-cols-2 gap-2 text-sm font-bold">
        <span className="truncate rounded-full px-2 py-2 text-center" style={{ border: "1px solid var(--border)" }}>{t("demo.notNow")}</span>
        <span className="landing-press truncate rounded-full px-2 py-2 text-center" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("tiles.together")}
        </span>
      </div>
    </div>
  );
}

/** A button that gets tapped: «Book» turns into «✓ Booked», then back. */
function TapButton({ idle, done }: { idle: string; done: string }) {
  return (
    <span className="landing-tap relative inline-grid shrink-0 overflow-hidden rounded-full px-3 py-1.5 text-sm font-bold">
      <span className="landing-tap-idle col-start-1 row-start-1 text-center">{idle}</span>
      <span className="landing-tap-done col-start-1 row-start-1 text-center">✓ {done}</span>
    </span>
  );
}

/** Today's class with its booking, and an independent coach for people without a box. */
export function BoxVisual() {
  const t = useTranslations("Landing");
  const row = "flex flex-col items-start gap-2 @xs:flex-row @xs:items-center @xs:justify-between @xs:gap-3";
  return (
    <div className={`${card} @container flex flex-col justify-center gap-3`} style={cardStyle} aria-hidden="true">
      <div className={row}>
        <div className="min-w-0">
          <p className="text-sm font-bold">{t("tiles.today")}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.classMeta")}</p>
        </div>
        <TapButton idle={t("tiles.book")} done={t("tiles.booked")} />
      </div>
      <div className="h-px" style={{ background: "var(--border)" }} />
      <div className={row}>
        <div className="min-w-0">
          <p className="text-sm font-bold">{t("tiles.coach")}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.coachMeta")}</p>
        </div>
        <span className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold" style={{ border: "1px solid var(--border)" }}>
          {t("tiles.appointment")}
        </span>
      </div>
    </div>
  );
}

/** What Palee does on its own, ticked off one by one. */
export function AutoVisual() {
  const t = useTranslations("Landing");
  return (
    <ul className={`${card} flex flex-col justify-center gap-2.5 text-sm font-semibold`} style={cardStyle} aria-hidden="true">
      {(["auto1", "auto2", "auto3", "auto4", "auto5"] as const).map((key, index) => (
        <li key={key} className="landing-tick flex items-start gap-2.5" style={delay(index * 0.45)}>
          <span
            className="landing-check grid size-5 shrink-0 place-items-center rounded-full text-xs"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)", ...delay(index * 0.45) }}
          >
            ✓
          </span>
          <span>{t(`tiles.${key}`)}</span>
        </li>
      ))}
    </ul>
  );
}

/** The 07:00 crew talking: messages pop in over a photo of the box. */
export function ClubVisual({ photo }: { photo: string }) {
  const t = useTranslations("Landing");
  return (
    <div className="relative min-h-56 flex-1 overflow-hidden rounded-2xl" aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={photo} alt="" className="landing-kenburns absolute inset-0 size-full object-cover" loading="lazy" />
      <div className="absolute inset-0" style={{ background: "linear-gradient(to top, var(--scrim), transparent 70%)" }} />
      <div className="absolute inset-x-3 bottom-3 grid gap-2 text-sm">
        <p className="landing-bubble max-w-[85%] justify-self-start rounded-2xl rounded-es-sm px-3 py-2" style={{ background: "var(--panel)", color: "var(--text)" }}>
          <b>{t("demo.post2Name")}</b> {t("demo.post2Text")}
        </p>
        <p className="landing-bubble justify-self-end rounded-2xl rounded-ee-sm px-3 py-2 font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)", ...delay(0.8) }}>
          🙋‍♀️ 🙋‍♂️ 💪
        </p>
      </div>
    </div>
  );
}
