"use client";

import { useTranslations } from "next-intl";

/**
 * ADR-760 (6A): «Να το δει και το μέλος» on every staff popup that asks
 * for a reason about a member. Always unticked when the popup opens; the
 * request sends `reason_shared` either way, and a shared row shows in the
 * member's Box › Συνδρομή › Ιστορικό with «Το box» as who did it.
 */
export function ShareWithMember({
  checked,
  onChange,
  disabled = false,
  testId,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  testId?: string;
}) {
  const t = useTranslations("ActivityLog");
  return (
    <label className="flex items-center gap-2 text-sm" style={{ color: disabled ? "var(--dim)" : "var(--text)" }}>
      <input
        type="checkbox"
        className="h-5 w-5 shrink-0"
        style={{ accentColor: "var(--primary)" }}
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
        data-testid={testId ?? "share-with-member"}
      />
      {t("shareWithMember")}
    </label>
  );
}
