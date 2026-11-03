"use client";

import { useTranslations } from "next-intl";
import type { CSSProperties } from "react";

import { ApiError } from "@/api/client";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { formatInZone, type ZonedFormat } from "@/lib/zoned-time";

import { initials } from "./lead-model";

const LEAD_ERRORS = new Set(["lead_converted", "lead_task_done", "lead_person_not_in_box", "lead_capture_conflict"]);

/** An API error in plain words; the lead-specific ones come from `Leads.error.*`. */
export function useLeadErrorText() {
  const t = useTranslations("Leads");
  const ui = useUiTranslations();
  return (error: unknown) => {
    const code = error instanceof ApiError ? error.payload.code : undefined;
    if (code && LEAD_ERRORS.has(code)) return t(`error.${code}`);
    return localizeError(error, ui);
  };
}

/** Moments on the box's clock (ADR-179), in the 24h clock of the UI language. */
export function useGymTime() {
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  return {
    zone,
    format: (at: string | Date, format: ZonedFormat = "day-time") => formatInZone(at, zone, locale, format),
  };
}

const avatarStyle: CSSProperties = {
  background: "color-mix(in srgb, var(--primary) 16%, var(--panel))",
  color: "var(--primary-strong)",
};

export function LeadAvatar({ name, size = "md" }: { name: string; size?: "sm" | "md" }) {
  return (
    <span
      aria-hidden="true"
      className={`grid shrink-0 place-items-center rounded-full font-bold ${size === "sm" ? "h-8 w-8 text-[11px]" : "h-10 w-10 text-xs"}`}
      style={avatarStyle}
    >
      {initials(name)}
    </span>
  );
}

/** A field label of the staff forms. */
export function FieldLabel({ htmlFor, children, required }: { htmlFor: string; children: string; required?: boolean }) {
  return (
    <label htmlFor={htmlFor} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
      {children}
      {required ? <span style={{ color: "var(--danger)" }}> *</span> : null}
    </label>
  );
}

/** The plain reason under a field that is wrong (UX rule: errors stay in the form). */
export function FieldError({ id, children }: { id: string; children: string | null | undefined }) {
  if (!children) return null;
  return (
    <p id={id} className="mt-1 text-xs font-semibold" style={{ color: "var(--danger)" }}>
      {children}
    </p>
  );
}

export function fieldStyle(invalid: boolean): CSSProperties {
  return {
    background: "var(--panel-muted)",
    border: `1px solid ${invalid ? "var(--danger)" : "var(--border-strong)"}`,
    color: "var(--text)",
  };
}

export const fieldClass = "w-full rounded-xl px-3 py-2.5 text-sm";
