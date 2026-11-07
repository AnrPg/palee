"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { InlineConfirm } from "@/components/ui/InlineConfirm";

/**
 * A button that asks on the page before it acts: tap once to see what will
 * happen, then confirm or keep things as they are. No browser dialog.
 */
export function ConfirmButton({
  label,
  question,
  confirmLabel,
  onConfirm,
  pending = false,
  disabled = false,
  testId,
}: {
  label: string;
  question: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  pending?: boolean;
  disabled?: boolean;
  testId?: string;
}) {
  const t = useTranslations("CheckIn");
  const [asking, setAsking] = useState(false);
  const base = "min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50";

  if (!asking) {
    return (
      <button
        type="button"
        className={base}
        disabled={disabled || pending}
        onClick={() => setAsking(true)}
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid={testId}
      >
        {label}
      </button>
    );
  }

  return (
    <InlineConfirm
      framed
      question={question}
      cancelLabel={t("keep")}
      confirmLabel={pending ? t("working") : confirmLabel}
      busy={pending}
      onCancel={() => setAsking(false)}
      onConfirm={() => {
        onConfirm();
        setAsking(false);
      }}
    />
  );
}
