"use client";

import { useTranslations } from "next-intl";

/**
 * The small product pictures of the guest landing (ADR-555): drawn with the
 * theme, in the app's own words, so every locale shows the real screens.
 * Each one is decoration next to text that says the same thing.
 */

const card = "rounded-2xl p-4 shadow-sm";
const cardStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" } as const;

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

export function PostVisual({ photo }: { photo?: string }) {
  const t = useTranslations("Landing");
  return (
    <div className={card} style={cardStyle} aria-hidden="true">
      <div className="flex items-center gap-3">
        <Avatar letter={t("demo.post1Name").slice(0, 1)} />
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("demo.post1Name")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.sharePost")}</p>
        </div>
      </div>
      {photo ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={photo} alt="" className="mt-3 aspect-[16/9] w-full rounded-xl object-cover" />
      ) : null}
      <p className="mt-3 text-sm font-semibold" style={{ color: "var(--primary)" }}>🔥 {t("demo.post1Kudos")}</p>
    </div>
  );
}

function Meter({ label, value }: { label: string; value: number }) {
  return (
    <div className="grid grid-cols-[5.5rem_1fr] items-center gap-3 text-sm">
      <span style={{ color: "var(--text-soft)" }}>{label}</span>
      <span className="h-2 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }}>
        <span className="block h-full rounded-full" style={{ width: `${value}%`, background: "var(--primary)" }} />
      </span>
    </div>
  );
}

export function JournalVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} grid gap-2.5`} style={cardStyle} aria-hidden="true">
      <p className="text-sm font-bold">{t("demo.today")}</p>
      <Meter label={t("tiles.mood")} value={72} />
      <Meter label={t("tiles.energy")} value={58} />
      <div className="grid grid-cols-[5.5rem_1fr] gap-3 text-sm">
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.sleep")}</span>
        <span className="font-semibold">{t("tiles.sleepValue")}</span>
      </div>
      <p className="text-sm italic" style={{ color: "var(--text-soft)" }}>{t("demo.note")}</p>
    </div>
  );
}

/** Ten weeks of a lift climbing, with the new PR popping out at the end. */
export function ProgressVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={card} style={cardStyle} aria-hidden="true">
      <div className="flex items-baseline justify-between gap-3 text-sm">
        <span className="font-bold">{t("tiles.lift")}</span>
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.weeks")}</span>
      </div>
      <svg viewBox="0 0 300 110" className="mt-2 w-full">
        <path
          className="landing-line"
          pathLength={1}
          d="M8 96 L38 90 L68 92 L98 80 L128 74 L158 76 L188 60 L218 52 L248 40 L284 18"
          fill="none"
          stroke="var(--primary)"
          strokeWidth="5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <circle className="landing-pop" cx="284" cy="18" r="9" fill="var(--spark)" stroke="var(--panel)" strokeWidth="3" />
      </svg>
      <div className="mt-1 flex items-center justify-between gap-3 text-sm">
        <span style={{ color: "var(--text-soft)" }}>{t("tiles.from")}</span>
        <span
          className="landing-pop rounded-full px-2.5 py-1 font-bold"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
        >
          {t("tiles.badge")}
        </span>
      </div>
    </div>
  );
}

export function PartnerVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={card} style={cardStyle} aria-hidden="true">
      <div className="flex items-center gap-3">
        <Avatar letter={t("tiles.partnerName").slice(0, 1)} tone="var(--heat)" />
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("demo.partnerName")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("demo.partnerMeta")}</p>
        </div>
      </div>
      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--success)" }}>{t("demo.verified")}</p>
      <div className="mt-3 grid grid-cols-2 gap-2 text-sm font-bold">
        <span className="rounded-full py-2 text-center" style={{ border: "1px solid var(--border)" }}>{t("demo.notNow")}</span>
        <span className="rounded-full py-2 text-center" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("tiles.together")}
        </span>
      </div>
    </div>
  );
}

export function BoxVisual() {
  const t = useTranslations("Landing");
  return (
    <div className={`${card} grid gap-3`} style={cardStyle} aria-hidden="true">
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("tiles.today")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.classMeta")}</p>
        </div>
        <span className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("tiles.book")}
        </span>
      </div>
      <div className="h-px" style={{ background: "var(--border)" }} />
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{t("tiles.coach")}</p>
          <p className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{t("tiles.coachMeta")}</p>
        </div>
        <span className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold" style={{ border: "1px solid var(--border)" }}>
          {t("tiles.appointment")}
        </span>
      </div>
    </div>
  );
}

export function AutoVisual() {
  const t = useTranslations("Landing");
  return (
    <ul className={`${card} grid gap-2 text-sm font-semibold`} style={cardStyle} aria-hidden="true">
      {(["auto1", "auto2", "auto3", "auto4", "auto5"] as const).map((key) => (
        <li key={key} className="flex items-start gap-2">
          <span style={{ color: "var(--primary)" }}>✓</span>
          <span>{t(`tiles.${key}`)}</span>
        </li>
      ))}
    </ul>
  );
}
