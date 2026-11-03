"use client";

import { useState, type ButtonHTMLAttributes, type CSSProperties, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";

import { integrationErrorKey } from "./connections-model";

/*
 * The small parts the Connections and door screens share. They follow the
 * SMS connection card (W3): muted cards, pill buttons, theme tokens only.
 */

export function Card({ children, testId }: { children: ReactNode; testId?: string }) {
  return (
    <div className="space-y-3 rounded-[1.5rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} data-testid={testId}>
      {children}
    </div>
  );
}

export function CardTitle({ title, hint, children }: { title: string; hint?: ReactNode; children?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-start gap-3">
      <div className="min-w-0 flex-1">
        <p className="font-semibold" style={{ color: "var(--text)" }}>{title}</p>
        {hint ? <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      </div>
      {children}
    </div>
  );
}

export { Pill } from "@/components/staff/staff-ui";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { children: ReactNode };

/** The one filled button of a screen state. */
export function PrimaryButton({ children, className = "", ...props }: ButtonProps) {
  return (
    <button type="button" {...props} className={`min-h-10 rounded-full px-5 text-sm font-bold disabled:opacity-50 ${className}`} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
      {children}
    </button>
  );
}

export function OutlineButton({ children, className = "", danger = false, ...props }: ButtonProps & { danger?: boolean }) {
  return (
    <button
      type="button"
      {...props}
      className={`min-h-10 rounded-full px-4 text-sm font-semibold disabled:opacity-50 ${className}`}
      style={{ border: `1px solid ${danger ? "var(--danger-border)" : "var(--border)"}`, color: danger ? "var(--danger-strong)" : "var(--text)" }}
    >
      {children}
    </button>
  );
}

/** «Άκυρο», «Πίσω»: a text button. */
export function TextButton({ children, className = "", ...props }: ButtonProps) {
  return (
    <button type="button" {...props} className={`min-h-10 px-2 text-sm font-semibold disabled:opacity-50 ${className}`} style={{ color: "var(--muted)" }}>
      {children}
    </button>
  );
}

export function inputStyle(invalid: boolean): CSSProperties {
  return {
    background: "var(--panel)",
    border: `1px solid ${invalid ? "var(--danger-border)" : "var(--border)"}`,
    color: "var(--text)",
  };
}

export const INPUT_CLASS = "w-full rounded-xl px-3 py-2 text-sm outline-none";

/** A labelled field with its reason underneath (form errors stay in the form). */
export function Field({ id, label, hint, error, children }: { id: string; label: string; hint?: ReactNode; error?: string | null; children: ReactNode }) {
  return (
    <div className="space-y-1">
      <label htmlFor={id} className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</label>
      {children}
      {error ? (
        <p id={`${id}-error`} className="text-xs" style={{ color: "var(--danger-strong)" }}>{error}</p>
      ) : hint ? (
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p>
      ) : null}
    </div>
  );
}

/**
 * A secret shown once (API key, signing secret, a door's event URL): copy it
 * now, it is never shown again.
 */
export function SecretOnce({ title, secret, hint, testId }: { title: string; secret: string; hint: string; testId?: string }) {
  const t = useTranslations("Connections");
  const [copied, setCopied] = useState(false);
  return (
    <div
      className="space-y-2 rounded-2xl p-4"
      style={{ background: "color-mix(in srgb, var(--success) 10%, var(--panel))", border: "1px solid color-mix(in srgb, var(--success) 45%, transparent)" }}
      data-testid={testId}
    >
      <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{title}</p>
      <code className="block break-all rounded-xl px-3 py-2 font-mono text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
        {secret}
      </code>
      <p className="text-xs leading-5" style={{ color: "var(--text-soft)" }}>{hint}</p>
      <OutlineButton onClick={() => void navigator.clipboard?.writeText(secret).then(() => setCopied(true))}>{copied ? t("copied") : t("copy")}</OutlineButton>
    </div>
  );
}

export { AdvancedDisclosure as Advanced } from "@/components/settings/AdvancedSettings";

/** The API's code in words (Connections and doors). */
export function useIntegrationError() {
  const t = useTranslations("Connections");
  return (error: unknown): string | null => {
    if (!error) return null;
    return t(integrationErrorKey(error instanceof ApiError ? error.payload.code : undefined));
  };
}

/** «dd/mm/yy hh:mm» in the 24h clock. */
export function useWhen() {
  const t = useTranslations("Connections");
  return (iso: string | null | undefined, locale: string) =>
    iso ? new Date(iso).toLocaleString(locale, { dateStyle: "short", timeStyle: "short", hourCycle: "h23" }) : t("never");
}
