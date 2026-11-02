"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  confirmStatusSubscription,
  fetchStatusHistory,
  fetchStatusOverview,
  subscribeToStatus,
  unsubscribeFromStatus,
  type StatusHistory,
  type StatusIncident,
  type StatusOverview,
} from "@/api/service-status";
import { PaleeMark } from "@/components/branding/PaleeMark";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { isAppLocale, persistLocaleCookie } from "@/i18n/locales";
import { useUiTranslations } from "@/i18n/ui";
import {
  DESKTOP_DAYS,
  PHONE_DAYS,
  STATUS_COMPONENTS,
  componentTone,
  dayBarColor,
  formatUptime,
  incidentText,
  lastDays,
  overallTone,
  toneColor,
  uptimeOver,
} from "@/lib/service-status";
import { formatInZone } from "@/lib/zoned-time";

/**
 * ADR-364 / ADR-366, W7 screen 1: the public status page, at status.palee.app
 * and /status. The public «Σχετικά» layout: the current incident with its
 * latest update, every component's last 30 (phone) or 90 (desktop) days, past
 * incidents and the email sign-up (double opt-in). No account needed.
 */

export const STATUS_QUERY_KEY = ["public-status"] as const;
const card = "rounded-[1.4rem] border p-5";
const cardStyle = { background: "var(--panel)", borderColor: "var(--border)" };

function useWideScreen() {
  const [wide, setWide] = useState(false);
  useEffect(() => {
    const query = window.matchMedia("(min-width: 640px)");
    const update = () => setWide(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return wide;
}

export function StatusPage() {
  const t = useTranslations("ServiceStatus");
  const i18n = useUiTranslations();
  const wide = useWideScreen();
  const overview = useQuery({
    queryKey: STATUS_QUERY_KEY,
    queryFn: ({ signal }) => fetchStatusOverview(signal),
    refetchInterval: 60_000,
  });
  const history = useQuery({
    queryKey: ["public-status", "history", DESKTOP_DAYS],
    queryFn: ({ signal }) => fetchStatusHistory(DESKTOP_DAYS, signal),
    refetchInterval: 5 * 60_000,
  });
  const days = wide ? DESKTOP_DAYS : PHONE_DAYS;

  return (
    <div className="mx-auto w-full max-w-4xl flex-1 px-4 py-12 sm:px-6 sm:py-16" style={{ color: "var(--text)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
        {t("eyebrow")}
      </p>
      <h1 className="mt-3 flex items-center gap-4 text-4xl font-bold tracking-tight sm:text-6xl">
        <PaleeMark className="h-12 w-12 shrink-0 sm:h-16 sm:w-16" />
        {i18n("brandName")}
      </h1>

      <SubscriptionLinkNotice />

      {overview.isError ? <ErrorNotice className="mt-8">{t("loadError")}</ErrorNotice> : null}
      {overview.isPending ? <p className="mt-8 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}

      {overview.data ? <NowSection overview={overview.data} /> : null}
      {overview.data && history.data ? (
        <ComponentHistory overview={overview.data} history={history.data} days={days} />
      ) : null}
      {history.data ? <PastIncidents history={history.data} /> : null}

      <SubscribeCard />

      <footer className="mt-8 flex flex-wrap gap-x-2 text-xs" style={{ color: "var(--dim)" }}>
        <span>{t("footerChecks")}</span>
        <LanguageSwitch />
        <span aria-hidden>·</span>
        <Link href="/about" className="font-semibold" style={{ color: "var(--dim)" }}>
          {i18n("brandName")}
        </Link>
      </footer>
    </div>
  );
}

function LanguageSwitch() {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const router = useRouter();
  if (locale === "en" || !isAppLocale("en")) return null;
  return (
    <>
      <span aria-hidden>·</span>
      <button
        type="button"
        lang="en"
        className="font-semibold"
        onClick={() => {
          persistLocaleCookie("en");
          router.refresh();
        }}
      >
        {t("inEnglish")}
      </button>
    </>
  );
}

function NowSection({ overview }: { overview: StatusOverview }) {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const others = overview.components.some((component) => component.status === "operational");

  if (overview.active.length === 0) {
    const tone = overallTone(overview.status);
    return (
      <>
        <section
          data-testid="status-now"
          className={`mt-8 ${card}`}
          style={{ ...cardStyle, borderInlineStartWidth: 6, borderInlineStartColor: toneColor(tone) }}
        >
          <h2 className="text-xl font-bold">{t(`overall.${overview.status}`)}</h2>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
            {overview.status === "unknown" ? t("unknownHelp") : t("allGoodHelp")}
          </p>
        </section>
        <Upcoming overview={overview} />
      </>
    );
  }

  return (
    <>
      {overview.active.map((incident) => {
        const text = incidentText(incident, locale);
        const latest = incident.updates[0];
        const tone = incident.kind === "maintenance" ? "info" : incident.impact === "minor" ? "warn" : "down";
        return (
          <section
            key={incident.id}
            data-testid="status-incident"
            className={`mt-8 ${card}`}
            style={{ ...cardStyle, borderInlineStartWidth: 6, borderInlineStartColor: toneColor(tone) }}
          >
            <h2 className="text-xl font-bold">{text.title}</h2>
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
              {t(`overall.${overview.status}`)}
              {" · "}
              {t("since", { time: formatInZone(incident.started_at, null, locale, "time") })}
              {others && incident.kind === "incident" ? ` · ${t("othersFine")}` : null}
            </p>
            {latest && text.body ? (
              <p className="mt-3 text-sm leading-6">
                <b>
                  {formatInZone(latest.created_at, null, locale, "time")} · {t(`incidentStatus.${latest.status}`)}.
                </b>{" "}
                {text.body}
                {text.machine ? (
                  <span className="ms-2 text-xs" style={{ color: "var(--dim)" }}>
                    ({t("machineTranslation")})
                  </span>
                ) : null}
              </p>
            ) : null}
          </section>
        );
      })}
      <Upcoming overview={overview} />
    </>
  );
}

function Upcoming({ overview }: { overview: StatusOverview }) {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  if (overview.upcoming.length === 0) return null;
  return (
    <section className={`mt-6 ${card} text-sm leading-6`} style={cardStyle} data-testid="status-upcoming">
      <h2 className="font-semibold">{t("upcomingTitle")}</h2>
      {overview.upcoming.map((maintenance) => (
        <p key={maintenance.id} className="mt-2">
          <b>{incidentText(maintenance, locale).title}</b>{" "}
          <span style={{ color: "var(--muted)" }}>
            · {maintenanceDay(maintenance, locale)} {timeRange(maintenance, locale)}
          </span>
        </p>
      ))}
    </section>
  );
}

function maintenanceDay(incident: StatusIncident, locale: string) {
  return formatInZone(incident.scheduled_for ?? incident.started_at, null, locale, { day: "numeric", month: "short" });
}

function timeRange(incident: StatusIncident, locale: string) {
  const from = incident.scheduled_for ?? incident.started_at;
  const until = incident.scheduled_until ?? incident.resolved_at;
  const start = formatInZone(from, null, locale, "time");
  return until ? `${start}–${formatInZone(until, null, locale, "time")}` : start;
}

function ComponentHistory({ overview, history, days }: { overview: StatusOverview; history: StatusHistory; days: number }) {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const now = new Map(overview.components.map((component) => [component.key, component.status]));
  const byKey = new Map(history.components.map((component) => [component.key, component]));

  return (
    <section className={`mt-6 ${card}`} style={cardStyle} data-testid="status-components" data-days={days}>
      <div className="flex justify-between text-xs" style={{ color: "var(--muted)" }}>
        <span>{t("lastDays", { count: days })}</span>
        <span>{t("today")}</span>
      </div>
      {STATUS_COMPONENTS.map((key) => {
        const status = now.get(key) ?? "unknown";
        const shown = lastDays(byKey.get(key)?.days ?? [], days);
        const uptime = uptimeOver(shown);
        return (
          <div key={key} className="mt-4" data-testid={`status-component-${key}`}>
            <div className="flex justify-between gap-3 text-[15px]">
              <b>{t(`component.${key}`)}</b>
              <span className="font-semibold" style={{ color: toneColor(componentTone(status)) }}>
                {t(`componentStatus.${status}`)}
              </span>
            </div>
            <div className="mt-2 flex gap-[2px]" role="img" aria-label={t("barsLabel", { name: t(`component.${key}`), count: days })}>
              {shown.map((day) => (
                <span
                  key={day.date}
                  title={`${formatInZone(Date.parse(day.date), "UTC", locale, { day: "numeric", month: "short" })} · ${t(`dayStatus.${day.status}`)}`}
                  className="h-[22px] flex-1 rounded-[2px]"
                  style={{ background: dayBarColor(day.status) }}
                />
              ))}
            </div>
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
              {uptime === null ? t("noData") : t("uptime", { value: formatUptime(uptime, locale) })}
            </p>
          </div>
        );
      })}
    </section>
  );
}

function PastIncidents({ history }: { history: StatusHistory }) {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const past = history.incidents.filter((incident) => incident.resolved_at);

  return (
    <>
      <h2 className="mt-10 text-2xl font-semibold">{t("previous")}</h2>
      <section className={`mt-4 ${card} text-sm leading-6`} style={cardStyle} data-testid="status-past">
        {past.length === 0 ? (
          <p style={{ color: "var(--muted)" }}>{t("noPrevious", { count: history.days })}</p>
        ) : (
          past.map((incident, index) => {
            const text = incidentText(incident, locale);
            const day = formatInZone(incident.started_at, null, locale, { day: "numeric", month: "short" });
            const detail =
              incident.kind === "maintenance"
                ? `${timeRange(incident, locale)} · ${t("completedWord")}`
                : `${duration(incident, t)} · ${t("resolvedWord")}`;
            return (
              <p key={incident.id} className={index > 0 ? "mt-2.5" : undefined}>
                <b>
                  {day} · {text.title}
                </b>{" "}
                <span style={{ color: "var(--muted)" }}>· {detail}</span>
              </p>
            );
          })
        )}
      </section>
    </>
  );
}

function duration(incident: StatusIncident, t: ReturnType<typeof useTranslations>) {
  const minutes = Math.max(
    1,
    Math.round((Date.parse(incident.resolved_at ?? incident.started_at) - Date.parse(incident.started_at)) / 60_000),
  );
  return minutes < 120 ? t("minutes", { count: minutes }) : t("hours", { count: Math.round(minutes / 60) });
}

function SubscribeCard() {
  const t = useTranslations("ServiceStatus");
  const locale = useLocale();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "invalid" | "error">("idle");
  const [sentTo, setSentTo] = useState("");

  async function submit() {
    const address = email.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
      setState("invalid");
      return;
    }
    setState("sending");
    try {
      await subscribeToStatus(address, locale);
      setSentTo(address);
      setState("sent");
    } catch (error) {
      setState(error instanceof ApiError && error.status === 422 ? "invalid" : "error");
    }
  }

  const invalid = state === "invalid";
  return (
    <section className={`mt-8 ${card}`} style={cardStyle} data-testid="status-subscribe">
      <h2 className="text-[15px] font-bold">{t("subscribeTitle")}</h2>
      <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("subscribeHelp")}</p>
      {state === "sent" ? (
        <p className="mt-3 text-sm" role="status" style={{ color: "var(--success)" }}>
          {t("subscribed", { email: sentTo })}
        </p>
      ) : (
        <form
          className="mt-3 flex flex-wrap gap-2.5"
          noValidate
          onSubmit={(event) => {
            event.preventDefault();
            void submit();
          }}
        >
          <div className="min-w-[180px] flex-1">
            <input
              type="email"
              autoComplete="email"
              aria-label={t("emailLabel")}
              aria-invalid={invalid || undefined}
              aria-describedby={invalid ? "status-email-error" : undefined}
              placeholder={t("emailPlaceholder")}
              value={email}
              onChange={(event) => {
                setEmail(event.target.value);
                if (state === "invalid" || state === "error") setState("idle");
              }}
              className="w-full rounded-2xl border px-4 py-3 text-sm"
              style={{
                background: "var(--panel-muted)",
                borderColor: invalid ? "var(--danger)" : "var(--border)",
                color: "var(--text)",
              }}
            />
            {invalid ? (
              <p id="status-email-error" className="mt-1 text-xs" style={{ color: "var(--danger)" }}>
                {t("emailInvalid")}
              </p>
            ) : null}
          </div>
          <button
            type="submit"
            disabled={state === "sending"}
            className="h-fit rounded-2xl px-5 py-3 text-sm font-semibold disabled:opacity-60"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {state === "sending" ? t("subscribing") : t("subscribe")}
          </button>
        </form>
      )}
      {state === "error" ? <ErrorNotice className="mt-3">{t("subscribeError")}</ErrorNotice> : null}
    </section>
  );
}

/** The links in status emails land here with `?confirm=` or `?unsubscribe=`. */
function SubscriptionLinkNotice() {
  const t = useTranslations("ServiceStatus");
  const params = useSearchParams();
  const confirm = params.get("confirm");
  const unsubscribe = params.get("unsubscribe");
  const [result, setResult] = useState<"confirmed" | "unsubscribed" | "expired" | null>(null);
  const sent = useRef(false);

  useEffect(() => {
    if (sent.current || (!confirm && !unsubscribe)) return;
    sent.current = true;
    const request = confirm ? confirmStatusSubscription(confirm) : unsubscribeFromStatus(unsubscribe ?? "");
    request
      .then(() => setResult(confirm ? "confirmed" : "unsubscribed"))
      .catch(() => setResult("expired"));
  }, [confirm, unsubscribe]);

  if (!result) return null;
  return (
    <p
      role="status"
      data-testid="status-link-result"
      className="mt-6 rounded-2xl px-4 py-3 text-sm"
      style={{
        background: "var(--panel-muted)",
        color: result === "expired" ? "var(--danger)" : "var(--text)",
      }}
    >
      {t(`link.${result}`)}
    </p>
  );
}
