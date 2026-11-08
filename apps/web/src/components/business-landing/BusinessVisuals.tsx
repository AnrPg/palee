"use client";

import type { CSSProperties, ReactNode } from "react";
import { useFormatter, useTranslations } from "next-intl";

import type { VisualId } from "@/components/business-landing/content";

/**
 * The small product pictures of the business landing (ADR-556), drawn with
 * the theme in the app's own words. Each one is decoration next to text that
 * says the same thing, so they are hidden from assistive technology.
 */

/** Lists in the messages are written «a | b | c». */
export const splitList = (value: string) => value.split(" | ").map((item) => item.trim());

const delay = (seconds: number): CSSProperties => ({ animationDelay: `${seconds}s` });
const card = "rounded-2xl p-4 text-sm";
const cardStyle: CSSProperties = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" };
const rowStyle: CSSProperties = { background: "var(--panel-muted)", border: "1px solid var(--border)" };

function Frame({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`${card} ${className}`} style={cardStyle} aria-hidden="true">
      {children}
    </div>
  );
}

function Check({ start }: { start: number }) {
  return (
    <span className="relative grid size-4 shrink-0 place-items-center rounded-[5px]" style={{ border: "2px solid var(--border-strong)" }}>
      <span
        className="landing-check absolute -inset-0.5 grid place-items-center rounded-[5px] text-[11px] font-black"
        style={{ background: "var(--spark)", color: "var(--spark-contrast)", ...delay(start) }}
      >
        ✓
      </span>
    </span>
  );
}

/** Two classes of the day filling slowly. */
function ScheduleVisual() {
  const t = useTranslations("BusinessLanding");
  const rows = splitList(t("console.box.rows")).slice(0, 2);
  const seats = [16, 12];
  const fills = [0.94, 0.75];
  return (
    <Frame className="grid gap-4">
      {rows.map((name, index) => (
        <div key={name} className="grid gap-1.5">
          <div className="flex justify-between gap-3">
            <b>{name}</b>
            <span style={{ color: "var(--muted)" }}>{t("visual.seats", { count: seats[index] })}</span>
          </div>
          <span className="block h-3 overflow-hidden rounded-full" style={rowStyle}>
            <span
              className="landing-slow-fill block h-full rounded-full"
              style={{ background: "var(--primary)", ["--fill" as string]: fills[index], ...delay(index * 1.5) }}
            />
          </span>
        </div>
      ))}
    </Frame>
  );
}

function ReceiptVisual() {
  const t = useTranslations("BusinessLanding");
  const format = useFormatter();
  return (
    <div className="grid place-items-center" aria-hidden="true">
      <div className="landing-print grid w-48 gap-1 rounded-t-lg p-3 pb-5 text-xs" style={cardStyle}>
        <b>{t("console.box.name")}</b>
        <span>{t("visual.receiptPackage")}</span>
        <span className="flex justify-between"><span>{t("visual.receiptTotal")}</span><b>{format.number(49, { style: "currency", currency: "EUR" })}</b></span>
        <span className="flex justify-between"><span>{t("visual.receiptCard")}</span><span>•••• 4242</span></span>
        <span
          className="landing-stamp mt-1 justify-self-center rounded-md px-2 py-0.5 text-xs font-black"
          style={{ border: "2px solid var(--primary)", color: "var(--primary)" }}
        >
          {t("visual.receiptStamp")}
        </span>
      </div>
    </div>
  );
}

const QR = "1110111100100110101011011101000101101011100111011";

function CheckinVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="grid place-items-center" aria-hidden="true">
      <div className="relative">
        <div className="relative grid size-28 grid-cols-7 gap-[3px] overflow-hidden rounded-2xl p-2.5" style={cardStyle}>
          {[...QR].map((bit, index) => (
            <span key={index} className="rounded-[2px]" style={{ background: bit === "1" ? "var(--text)" : "transparent" }} />
          ))}
          <span className="landing-scan absolute inset-x-0 h-[3px]" style={{ background: "var(--spark)" }} />
        </div>
        <span
          className="landing-pop absolute -end-4 -top-3 rounded-full px-2.5 py-1 text-xs font-black"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)", animationDuration: "2.4s" }}
        >
          {t("visual.checkedIn")}
        </span>
      </div>
    </div>
  );
}

/** The box website cycling through home, schedule and packages. */
function WebsiteVisual() {
  const t = useTranslations("BusinessLanding");
  const pages = [
    { title: t("visual.siteHome"), meta: t("visual.siteHomeMeta"), button: t("visual.siteJoin"), bg: "var(--deep)", fg: "var(--deep-contrast)", btnBg: "var(--spark)", btnFg: "var(--spark-contrast)" },
    { title: t("visual.siteSchedule"), meta: t("visual.siteScheduleMeta"), button: t("visual.siteBook"), bg: "var(--primary)", fg: "var(--primary-contrast)", btnBg: "var(--deep)", btnFg: "var(--deep-contrast)" },
    { title: t("visual.sitePackages"), meta: t("visual.sitePackagesMeta"), button: t("visual.siteBuy"), bg: "var(--spark)", fg: "var(--spark-contrast)", btnBg: "var(--deep)", btnFg: "var(--deep-contrast)" },
  ];
  return (
    <div className="w-full overflow-hidden rounded-2xl shadow-(--shadow-lg)" style={{ border: "1px solid var(--border)", background: "var(--panel)" }} aria-hidden="true">
      <div className="flex h-7 items-center gap-1.5 px-3" style={{ background: "var(--panel-muted)" }}>
        {[0, 1, 2].map((dot) => (
          <span key={dot} className="size-1.5 rounded-full" style={{ background: "var(--border-strong)" }} />
        ))}
        <span className="ms-3 max-w-56 flex-1 truncate rounded-full px-3 text-xs" style={{ background: "var(--panel)", color: "var(--muted)" }}>
          {t("visual.siteDomain")}
        </span>
      </div>
      <div className="relative h-44">
        {pages.map((page, index) => (
          <div
            key={page.title}
            className="landing-site absolute inset-0 grid content-center gap-1.5 p-5"
            style={{ background: page.bg, color: page.fg, ...delay(index * 3) }}
          >
            <b className="text-2xl font-black tracking-tight">{page.title}</b>
            <span className="text-sm opacity-80">{page.meta}</span>
            <span
              className="landing-pulse mt-1.5 justify-self-start rounded-full px-3.5 py-1.5 text-xs font-extrabold"
              style={{ background: page.btnBg, color: page.btnFg }}
            >
              {page.button}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/** A voice log turning into a WOD, then a scaling suggestion the coach approves. */
function AiVisual() {
  const t = useTranslations("BusinessLanding");
  const row: CSSProperties = { background: "color-mix(in srgb, var(--deep-contrast) 10%, transparent)" };
  return (
    <div className="grid w-full gap-2 text-xs" aria-hidden="true">
      <div className="landing-pop flex items-center gap-2.5 rounded-xl p-2.5" style={{ ...row, animationDuration: "9s" }}>
        <span className="landing-pulse" style={{ color: "var(--heat)" }}>●</span>
        <span className="flex h-5 shrink-0 items-center gap-0.5">
          {Array.from({ length: 14 }, (_, index) => (
            <span key={index} className="landing-wave w-[3px] rounded-sm" style={{ background: "var(--spark)", ...delay((index % 4) * 0.2) }} />
          ))}
        </span>
        <span className="min-w-0 truncate opacity-75">{t("visual.aiSaid")}</span>
      </div>
      <div className="landing-pop grid gap-0.5 rounded-xl p-2.5" style={{ ...row, animationDuration: "9s", ...delay(1.4) }}>
        <b style={{ color: "var(--spark)" }}>→ {t("visual.aiParsed")}</b>
        <span>{t("visual.aiParsedMeta")}</span>
      </div>
      <div className="landing-pop flex items-center gap-2.5 rounded-xl p-2.5" style={{ ...row, animationDuration: "9s", ...delay(2.8) }}>
        <span className="size-2.5 shrink-0 rounded-full" style={{ background: "var(--spark)" }} />
        <span className="min-w-0">
          <b>{t("visual.aiSuggestion")}</b>
          <br />
          {t("visual.aiSuggestionMeta")}
        </span>
        <span className="ms-auto shrink-0 rounded-full px-2 py-0.5 font-extrabold" style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}>
          {t("visual.aiApproved")}
        </span>
      </div>
    </div>
  );
}

function WodVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="grid w-full max-w-64 gap-1 rounded-2xl p-3.5 text-sm" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }} aria-hidden="true">
      <b style={{ color: "var(--spark)" }}>{t("visual.wodTitle")}</b>
      {splitList(t("visual.wodLines")).map((line, index) => (
        <span key={line} className="overflow-hidden whitespace-nowrap">
          <span className="landing-type block overflow-hidden" style={delay(index * 0.6)}>{line}</span>
        </span>
      ))}
    </div>
  );
}

/** EMOM on the TV: a ring runs down while the seconds count. */
function TimerVisual() {
  return (
    <div className="grid place-items-center" aria-hidden="true">
      <div className="relative grid size-32 place-items-center">
        <svg viewBox="0 0 120 120" className="absolute inset-0 -rotate-90">
          <circle cx="60" cy="60" r="50" fill="none" strokeWidth="9" stroke="color-mix(in srgb, currentColor 15%, transparent)" />
          <circle className="landing-ring" cx="60" cy="60" r="50" fill="none" strokeWidth="9" strokeLinecap="round" stroke="var(--spark)" />
        </svg>
        <b className="text-3xl font-black tabular-nums">00:42</b>
        <small className="absolute bottom-7 text-[10px] font-extrabold tracking-[0.14em]" style={{ color: "var(--spark)" }}>EMOM</small>
      </div>
    </div>
  );
}

function RolesVisual() {
  const t = useTranslations("BusinessLanding");
  const roles = splitList(t("visual.roles"));
  const branches = splitList(t("visual.branches"));
  return (
    <div className="flex flex-wrap justify-center gap-1.5" aria-hidden="true">
      {[...roles, ...branches].map((label, index) => (
        <span
          key={label}
          className="landing-pop rounded-full px-2.5 py-1 text-xs font-bold"
          style={{
            ...(index >= roles.length ? { background: "var(--spark)", color: "var(--spark-contrast)" } : rowStyle),
            ...delay(index * 0.25),
          }}
        >
          {label}
        </span>
      ))}
    </div>
  );
}

function ClubVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <Frame className="relative w-full max-w-64">
      <p><b>{t("visual.clubName")}</b> · <span style={{ color: "var(--muted)" }}>{t("visual.clubWhere")}</span></p>
      <div className="relative mt-2 h-20 overflow-hidden rounded-xl" style={{ background: "linear-gradient(135deg, var(--primary), var(--deep))" }}>
        <b className="absolute bottom-1.5 start-2.5 text-base font-black" style={{ color: "var(--spark)" }}>{t("visual.clubPr")}</b>
      </div>
      <p className="mt-2 font-bold" style={{ color: "var(--heat)" }}>♥ {t("visual.clubKudos")}</p>
      {[0, 0.8, 1.6, 2.2].map((start, index) => (
        <span key={start} className="landing-float absolute bottom-5 end-4" style={{ color: "var(--heat)", insetInlineEnd: `${1 + (index % 3) * 0.4}rem`, ...delay(start) }}>
          ♥
        </span>
      ))}
    </Frame>
  );
}

const BARS = [45, 62, 55, 78, 70, 88, 96];

function StatsVisual() {
  return (
    <div className="flex h-28 w-full items-end gap-2" aria-hidden="true">
      {BARS.map((height, index) => (
        <span
          key={index}
          className="landing-grow flex-1 rounded-t-md"
          style={{ height: `${height}%`, background: index === BARS.length - 1 ? "var(--spark)" : "var(--primary)", ...delay(index * 0.1) }}
        />
      ))}
    </div>
  );
}

function ClientsVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <Frame className="grid w-full gap-2">
      <b>{t("tiles.clients.title")}</b>
      {splitList(t("visual.clients")).map((line, index) => (
        <span key={line} className="landing-pop flex items-center gap-2" style={delay(index * 0.4)}>
          <span className="size-6 shrink-0 rounded-full" style={{ background: "var(--primary)" }} />
          {line}
        </span>
      ))}
    </Frame>
  );
}

function CoachPayVisual() {
  const t = useTranslations("BusinessLanding");
  const format = useFormatter();
  const lines: [string, string][] = [
    [t("visual.coachPayClasses"), "18"],
    [t("visual.coachPaySessions"), "9"],
    [t("visual.coachPayTotal"), format.number(720, { style: "currency", currency: "EUR", maximumFractionDigits: 0 })],
  ];
  return (
    <Frame className="grid w-full gap-1.5">
      <b style={{ color: "var(--primary)" }}>{t("visual.coachPayTitle")}</b>
      {lines.map(([label, value], index) => (
        <span key={label} className="landing-tick flex justify-between gap-3" style={{ ...(index === 2 ? { borderTop: "1px solid var(--border)", paddingTop: "0.25rem" } : {}), ...delay(index * 0.5) }}>
          <span>{label}</span>
          <b className="tabular-nums">{value}</b>
        </span>
      ))}
    </Frame>
  );
}

/** Two lines drawing themselves, with the insights popping beside them. */
function InsightsVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="relative w-full" aria-hidden="true">
      <svg viewBox="0 0 320 140" className="block h-auto w-full">
        {[35, 70, 105].map((y) => (
          <line key={y} x1="0" x2="320" y1={y} y2={y} stroke="var(--border)" strokeWidth="1" />
        ))}
        <path className="landing-draw" pathLength={1} d="M5 100 L50 88 L95 92 L140 70 L185 74 L230 52 L275 46 L315 30" fill="none" stroke="var(--primary)" strokeWidth="3" strokeLinecap="round" />
        <path className="landing-draw" pathLength={1} d="M5 60 L50 62 L95 58 L140 66 L185 80 L230 92 L275 96 L315 104" fill="none" stroke="var(--spark)" strokeWidth="3" strokeLinecap="round" style={delay(0.4)} />
      </svg>
      <span className="landing-pop absolute end-1 top-[60%] max-w-[60%] rounded-lg px-2.5 py-1.5 text-[11px] font-bold shadow-(--shadow-lg)" style={{ ...cardStyle, ...delay(1.8), animationDuration: "7s" }}>
        {t("visual.insightDrop")}
      </span>
      <span className="landing-pop absolute start-1 top-0 max-w-[60%] rounded-lg px-2.5 py-1.5 text-[11px] font-bold shadow-(--shadow-lg)" style={{ ...cardStyle, ...delay(3.2), animationDuration: "7s" }}>
        {t("visual.insightRisk")}
      </span>
    </div>
  );
}

function FiscalVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="grid w-full gap-1.5 text-xs" aria-hidden="true">
      {splitList(t("visual.fiscal")).map((line, index) => (
        <span key={line} className="flex items-center gap-2 rounded-xl px-2.5 py-2" style={rowStyle}>
          <Check start={index * 0.9} />
          <span className="min-w-0 flex-1 truncate">{line}</span>
          <b>{t("visual.fiscalDone")}</b>
        </span>
      ))}
    </div>
  );
}

function MachinesVisual() {
  const t = useTranslations("BusinessLanding");
  const states = splitList(t("visual.machineStates"));
  const tones: CSSProperties[] = [
    { background: "var(--heat)", color: "var(--heat-contrast)" },
    { background: "var(--primary)", color: "var(--primary-contrast)" },
    { background: "var(--spark)", color: "var(--spark-contrast)" },
  ];
  return (
    <div className="grid w-full gap-1.5 text-xs" aria-hidden="true">
      {splitList(t("visual.machines")).map((machine, row) => (
        <span key={machine} className="flex items-center justify-between gap-2 rounded-xl px-2.5 py-2" style={rowStyle}>
          <b className="truncate">{machine}</b>
          <span className="inline-grid">
            {states.map((state, index) => (
              <span
                key={state}
                className="landing-state col-start-1 row-start-1 whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-extrabold"
                style={{ ...tones[index], ...delay(index * 3 + row * 0.6) }}
              >
                {state}
              </span>
            ))}
          </span>
        </span>
      ))}
    </div>
  );
}

function StaffPayVisual() {
  const t = useTranslations("BusinessLanding");
  const format = useFormatter();
  const values = [840, 40, 610, -15].map((euros, index) =>
    format.number(euros, { style: "currency", currency: "EUR", maximumFractionDigits: 0, signDisplay: index % 2 === 1 ? "always" : "auto" }),
  );
  return (
    <div className="grid w-full gap-1.5 text-xs" aria-hidden="true">
      {splitList(t("visual.staffPayLines")).map((line, index) => (
        <span key={line} className="landing-tick flex justify-between gap-2 rounded-xl px-2.5 py-2" style={{ ...rowStyle, ...delay(index * 0.4) }}>
          <span className="truncate">{line}</span>
          <b className="tabular-nums">{values[index]}</b>
        </span>
      ))}
    </div>
  );
}

function CleaningVisual() {
  const t = useTranslations("BusinessLanding");
  const times = ["07:00", "10:00", "14:00", "21:00"];
  return (
    <div className="grid w-full gap-1.5 text-xs" aria-hidden="true">
      {splitList(t("visual.cleaning")).map((line, index) => (
        <span key={line} className="flex items-center gap-2 rounded-xl px-2.5 py-2" style={rowStyle}>
          <Check start={index * 0.9} />
          <span className="min-w-0 flex-1 truncate">{line}</span>
          <span className="rounded-full px-2 py-0.5 font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>{times[index]}</span>
        </span>
      ))}
    </div>
  );
}

const STOCK: { from: number; to: number; low: boolean }[] = [
  { from: 1, to: 0.25, low: true },
  { from: 0.9, to: 0.7, low: false },
  { from: 0.8, to: 0.15, low: true },
  { from: 1, to: 0.55, low: false },
];

function StockVisual() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="grid w-full grid-cols-[5.5rem_1fr_auto] items-center gap-x-2 gap-y-2 text-xs" aria-hidden="true">
      {splitList(t("visual.stock")).map((item, index) => (
        <span key={item} className="contents">
          <span className="truncate">{item}</span>
          <span className="h-2 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }}>
            <span className="landing-drain block h-full" style={{ background: "var(--primary)", ["--from" as string]: STOCK[index].from, ["--to" as string]: STOCK[index].to }} />
          </span>
          <span
            className={`rounded-full px-2 py-0.5 text-[10px] font-extrabold ${STOCK[index].low ? "landing-low" : "invisible"}`}
            style={{ background: "var(--heat)", color: "var(--heat-contrast)" }}
          >
            {t("visual.stockLow")}
          </span>
        </span>
      ))}
    </div>
  );
}

function CampaignsVisual() {
  const t = useTranslations("BusinessLanding");
  const post = <span className="block h-10 rounded-xl" style={rowStyle} />;
  return (
    <div className="relative h-40 w-full max-w-72 overflow-hidden" aria-hidden="true">
      <div className="landing-feed absolute inset-x-0 top-0 grid gap-1.5">
        {post}
        <span className="grid gap-0.5 rounded-xl p-2.5 text-xs shadow-(--shadow-lg)" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}>
          <small className="text-[10px] font-extrabold uppercase tracking-[0.1em]" style={{ color: "var(--spark)" }}>{t("visual.adSponsored")}</small>
          <b>{t("visual.adTitle")}</b>
          <span>{t("visual.adBody")}</span>
        </span>
        {post}
        {post}
      </div>
    </div>
  );
}

function OfferVisual() {
  return (
    <div className="grid place-items-center" aria-hidden="true">
      <OfferCoupon />
    </div>
  );
}

function OfferCoupon() {
  const t = useTranslations("BusinessLanding");
  return (
    <div className="landing-sway relative grid w-full max-w-64 gap-0.5 rounded-2xl px-4 py-3 text-xs" style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}>
      <span>{t("visual.offerPartner")}</span>
      <b className="text-lg font-black">{t("visual.offerTitle")}</b>
      <span>{t("visual.offerBody")}</span>
    </div>
  );
}


/** The e-shop: products, «Add» tapped, the cart counting up. */
function ShopVisual() {
  const t = useTranslations("BusinessLanding");
  const items = splitList(t("visual.shopItems"));
  const prices = splitList(t("visual.shopPrices"));
  return (
    <Frame className="grid w-full gap-3">
      <span className="flex items-center justify-between gap-2">
        <b>{t("visual.shopTitle")}</b>
        <span className="relative rounded-full px-2.5 py-1 text-xs font-bold" style={rowStyle}>
          {t("visual.shopCart")}
          <span className="landing-pop absolute -end-2 -top-2 grid size-5 place-items-center rounded-full text-[10px] font-black" style={{ background: "var(--heat)", color: "var(--heat-contrast)", animationDuration: "4s", ...delay(1) }}>
            1
          </span>
        </span>
      </span>
      <span className="grid grid-cols-3 gap-2">
        {items.map((item, index) => (
          <span key={item} className="grid gap-1 rounded-xl p-2 text-xs" style={rowStyle}>
            <span className="landing-bob aspect-square rounded-lg" style={{ background: index === 1 ? "var(--spark)" : "linear-gradient(135deg, var(--primary), var(--deep))", ...delay(index * -1.3) }} />
            <b className="truncate">{item}</b>
            <span className="flex items-center justify-between gap-1">
              <span className="tabular-nums">{prices[index]}</span>
              <span
                className={`rounded-full px-1.5 text-[10px] font-extrabold ${index === 0 ? "landing-tap" : ""}`}
                style={index === 0 ? undefined : { background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("visual.shopAdd")}
              </span>
            </span>
          </span>
        ))}
      </span>
    </Frame>
  );
}

const VISUALS: Record<VisualId, () => ReactNode> = {
  schedule: ScheduleVisual,
  receipt: ReceiptVisual,
  checkin: CheckinVisual,
  website: WebsiteVisual,
  ai: AiVisual,
  wod: WodVisual,
  timer: TimerVisual,
  roles: RolesVisual,
  club: ClubVisual,
  stats: StatsVisual,
  clients: ClientsVisual,
  coachPay: CoachPayVisual,
  insights: InsightsVisual,
  fiscal: FiscalVisual,
  machines: MachinesVisual,
  staffPay: StaffPayVisual,
  cleaning: CleaningVisual,
  stock: StockVisual,
  campaigns: CampaignsVisual,
  offer: OfferVisual,
  shop: ShopVisual,
};

export function BusinessVisual({ id }: { id: VisualId }) {
  const Visual = VISUALS[id];
  return <Visual />;
}
