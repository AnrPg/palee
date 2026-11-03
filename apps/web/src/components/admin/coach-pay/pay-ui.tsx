"use client";

import { useTranslations } from "next-intl";
import type { ReactNode } from "react";

import { FieldError } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { dateKeyInZone } from "@/lib/zoned-time";

import { calendarNoon } from "./coach-pay";
import { useOrganizationTimeZone } from "@/lib/organization-slug";

/*
 * Small parts every «Αμοιβές coaches» screen shares: money in the record's
 * currency, the «Καθαρά» mark of a net line (ADR-382: net lines are marked
 * with a colour), «Μικτά X · Καθαρά Y», initials and form rows.
 */

export const controlClass = "w-full rounded-xl px-3 py-2.5 text-sm outline-none";
export const controlStyle = { background: "var(--panel)", color: "var(--text)" } as const;

export function useMoney(currency = "EUR") {
  const locale = useUiLocale();
  return (cents: number) => formatMinorUnits(locale, cents, currency);
}

export function usePercent() {
  const locale = useUiLocale();
  return (bps: number) => new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 2 }).format(bps / 10000);
}

/** A gym-local calendar date (YYYY-MM-DD) as «31/10/2026». */
export function useShortDate() {
  const locale = useUiLocale();
  return (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "numeric", year: "numeric", timeZone: "UTC" }).format(calendarNoon(iso));
}

/** The gym-local date today (ADR-176/179), as YYYY-MM-DD. */
export function useGymToday(): string {
  const zone = useOrganizationTimeZone();
  return dateKeyInZone(new Date(), zone);
}

/** «Καθαρά»: a net line or rule, in the info colour so it is seen at a glance. */
export function NetMark() {
  const t = useTranslations("CoachPay");
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-[0.08em]"
      style={{ background: "color-mix(in srgb, var(--info) 14%, transparent)", color: "var(--info)", border: "1px solid var(--info)" }}
      data-testid="net-mark"
    >
      {t("net")}
    </span>
  );
}

/** «Μικτά 640,00 € · Καθαρά 30,00 €»; the net part only when there is some. */
export function GrossNet({ gross, net, currency, testId }: { gross: number; net: number; currency: string; testId?: string }) {
  const t = useTranslations("CoachPay");
  const money = useMoney(currency);
  return (
    <span className="tabular-nums" data-testid={testId}>
      {t("grossAmount", { amount: money(gross) })}
      {net !== 0 ? (
        <>
          {" · "}
          <span style={{ color: "var(--info)" }}>{t("netAmount", { amount: money(net) })}</span>
        </>
      ) : null}
    </span>
  );
}

export function Initials({ name }: { name: string }) {
  const letters = name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]!.toLocaleUpperCase())
    .join("");
  return (
    <span
      aria-hidden="true"
      className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-bold"
      style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
    >
      {letters || "?"}
    </span>
  );
}

export function FormRow({ label, htmlFor, hint, error, errorId, children }: { label: string; htmlFor?: string; hint?: string; error?: string | null; errorId?: string; children: ReactNode }) {
  return (
    <div className="space-y-1.5">
      {htmlFor ? (
        <label htmlFor={htmlFor} className="block text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          {label}
        </label>
      ) : (
        <p className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{label}</p>
      )}
      {children}
      {hint && !error ? <p className="text-xs" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      {errorId ? <FieldError id={errorId}>{error}</FieldError> : null}
    </div>
  );
}

/** Pills to pick one option (kind, frequency, basis). */
export function Choice<T extends string>({ value, options, onChange, label, testId }: { value: T; options: Array<{ value: T; label: string }>; onChange: (value: T) => void; label: string; testId?: string }) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-2" data-testid={testId}>
      {options.map((option) => {
        const on = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(option.value)}
            className="rounded-full px-3.5 py-2 text-sm font-semibold"
            style={
              on
                ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                : { background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }
            }
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

/** Chips to pick several (roles, counted statuses). */
export function Chips<T extends string>({ value, options, onChange, label, invalid }: { value: T[]; options: Array<{ value: T; label: string }>; onChange: (value: T[]) => void; label: string; invalid?: boolean }) {
  return (
    <div role="group" aria-label={label} className="flex flex-wrap gap-2">
      {options.map((option) => {
        const on = value.includes(option.value);
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={on}
            onClick={() => onChange(on ? value.filter((item) => item !== option.value) : [...value, option.value])}
            className="rounded-full px-3.5 py-2 text-sm font-semibold"
            style={{
              background: on ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
              color: on ? "var(--primary)" : "var(--text-soft)",
              border: `1px solid ${invalid ? "var(--danger)" : on ? "var(--primary)" : "var(--border)"}`,
            }}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

/** «Προχωρημένα»: rare options, closed until opened. */
export function Advanced({ open, onToggle, children }: { open: boolean; onToggle: () => void; children: ReactNode }) {
  const t = useTranslations("CoachPay");
  return (
    <div className="rounded-2xl" style={{ border: "1px solid var(--border)" }}>
      <button type="button" aria-expanded={open} className="flex w-full items-center justify-between px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={onToggle}>
        {t("advanced")}
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? <div className="space-y-4 px-4 pb-4">{children}</div> : null}
    </div>
  );
}

/** Saves a downloaded file (CSV, PDF) under `name`. */
export function saveFile(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
