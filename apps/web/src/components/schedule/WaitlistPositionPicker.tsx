"use client";

import { useTranslations } from "next-intl";

import type { WaitlistPosition } from "@/api/admin-users";

/**
 * ADR-790 (ANR pick 2B): where staff put someone on a full class's waitlist,
 * chosen each time: «Στο τέλος (θέση N)», the place joining themselves would
 * give, or «Πρώτος στη σειρά». Used by the class page's «+ Προσθήκη» and the
 * profile's «Κράτηση ή μετακίνηση».
 */
export function WaitlistPositionPicker({
  value,
  onChange,
  endPlace,
  disabled = false,
  name,
}: {
  value: WaitlistPosition;
  onChange: (position: WaitlistPosition) => void;
  /** The place «Στο τέλος» gives, from the server; null when unknown. */
  endPlace: number | null | undefined;
  disabled?: boolean;
  /** The radio group's name, unique on the page. */
  name: string;
}) {
  const t = useTranslations("StaffWaitlist");
  const choices: { value: WaitlistPosition; label: string }[] = [
    { value: "end", label: endPlace ? t("positionEnd", { place: endPlace }) : t("positionEndPlain") },
    { value: "first", label: t("positionFirst") },
  ];

  return (
    <fieldset className="space-y-2" data-testid="waitlist-position">
      <legend className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
        {t("position")}
      </legend>
      {choices.map((choice) => {
        const selected = value === choice.value;
        return (
          <label
            key={choice.value}
            className="flex min-h-11 cursor-pointer items-center gap-3 rounded-2xl px-3 text-sm font-semibold"
            style={{
              background: "var(--panel)",
              color: "var(--text)",
              border: selected ? "2px solid var(--primary)" : "1px solid var(--border)",
            }}
          >
            <input
              type="radio"
              name={name}
              value={choice.value}
              checked={selected}
              disabled={disabled}
              onChange={() => onChange(choice.value)}
              style={{ accentColor: "var(--primary)" }}
            />
            {choice.label}
          </label>
        );
      })}
    </fieldset>
  );
}
