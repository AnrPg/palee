"use client";

import { useTranslations } from "next-intl";
import { useEffect, useId } from "react";

import type { StaffProgramme } from "@/api/programmes";
import { inputClass, inputStyle } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { GOALS, LEVELS, useProgrammeLabels } from "@/components/programmes/programme-ui";

import { ProgrammeCoverField } from "./CoverEditor";
import { addEquipment, addableEquipment, removeEquipment, shownEquipment, type Draft, type EquipmentKey } from "./programme-editor-model";

/**
 * «Στοιχεία» (board 1κ A, 1μ A): title, summary, level and goal; the cover
 * photo (ADR-541); «κύριος εξοπλισμός» derived from the WODs, which the
 * author may add to or take from, and «περίπου ανά προπόνηση» (ADR-542).
 * Price, preview days and refunds are asked in «Δημοσίευση…».
 */
export function ProgrammeDetails({
  programme,
  draft,
  token,
  focus,
  onChange,
}: {
  programme: StaffProgramme;
  draft: Draft;
  token: string;
  focus: { field: "title" | "summary"; at: number } | null;
  onChange: (patch: Partial<Draft>) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const labels = useProgrammeLabels();
  const ids = { title: useId(), titleError: useId(), summary: useId(), summaryHint: useId(), level: useId(), goal: useId() };
  const titleInvalid = draft.title.trim().length < 2;

  useEffect(() => {
    if (!focus) return;
    document.getElementById(focus.field === "title" ? ids.title : ids.summary)?.focus();
    // Only a new request moves the focus.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focus?.at]);

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)]" data-testid="programme-details">
      <section className="flex min-w-0 flex-col gap-4 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <div>
          <label htmlFor={ids.title} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{tp("fieldTitle")}</label>
          <input
            id={ids.title}
            className={inputClass}
            style={titleInvalid ? { ...inputStyle, borderColor: "var(--danger)" } : inputStyle}
            value={draft.title}
            maxLength={120}
            aria-invalid={titleInvalid}
            aria-describedby={titleInvalid ? ids.titleError : undefined}
            onChange={(event) => onChange({ title: event.target.value })}
            data-testid="programme-title"
          />
          {titleInvalid ? <p id={ids.titleError} className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{tp("titleRequired")}</p> : null}
        </div>
        <div>
          <label htmlFor={ids.summary} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("summary")}</label>
          <textarea
            id={ids.summary}
            className={inputClass}
            style={inputStyle}
            rows={3}
            maxLength={600}
            value={draft.summary}
            placeholder={t("summaryPlaceholder")}
            aria-describedby={ids.summaryHint}
            onChange={(event) => onChange({ summary: event.target.value })}
            data-testid="programme-summary"
          />
          <p id={ids.summaryHint} className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("summaryHint")}</p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor={ids.level} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{tp("fieldLevel")}</label>
            <Select id={ids.level} className={inputClass} style={inputStyle} value={draft.level} onValueChange={(value) => onChange({ level: value as Draft["level"] })}>
              {LEVELS.map((level) => <option key={level} value={level}>{labels.level(level)}</option>)}
            </Select>
          </div>
          <div>
            <label htmlFor={ids.goal} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{tp("fieldGoal")}</label>
            <Select id={ids.goal} className={inputClass} style={inputStyle} value={draft.goal} onValueChange={(value) => onChange({ goal: value as Draft["goal"] })}>
              {GOALS.map((goal) => <option key={goal} value={goal}>{labels.goal(goal)}</option>)}
            </Select>
          </div>
        </div>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("sellingNote")}</p>
      </section>

      <section className="flex min-w-0 flex-col gap-5 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <ProgrammeCoverField programme={programme} token={token} />
        <EquipmentField
          derived={programme.facts?.equipment ?? []}
          added={draft.equipment}
          removed={draft.equipmentRemoved}
          onChange={(next) => onChange(next)}
        />
        <div>
          <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("minutesTitle")}</h3>
          {programme.facts?.minutes_per_session ? (
            <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }} data-testid="programme-minutes">
              {t("minutesValue", { minutes: programme.facts.minutes_per_session })}
            </p>
          ) : (
            <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("minutesUnknown")}</p>
          )}
        </div>
      </section>
    </div>
  );
}

function EquipmentField({
  derived,
  added,
  removed,
  onChange,
}: {
  derived: EquipmentKey[];
  added: EquipmentKey[];
  removed: EquipmentKey[];
  onChange: (next: { equipment: EquipmentKey[]; equipmentRemoved: EquipmentKey[] }) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const te = useTranslations("Equipment");
  const addId = useId();
  const shown = shownEquipment(derived, added, removed);
  const addable = addableEquipment(derived, added, removed);
  const takenAway = removed.filter((key) => derived.includes(key));
  return (
    <div className="flex flex-col gap-2" data-testid="programme-equipment">
      <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("equipmentTitle")}</h3>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("equipmentHint")}</p>
      {shown.length ? (
        <ul className="flex flex-wrap gap-1.5">
          {shown.map((key) => (
            <li key={key} className="flex items-center gap-0.5 rounded-full py-0.5 pe-0.5 ps-3 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}>
              {te(key)}
              <button
                type="button"
                onClick={() => onChange(removeEquipment(derived, added, removed, key))}
                aria-label={t("equipmentRemove", { name: te(key) })}
                className="grid h-8 w-8 place-items-center rounded-full"
                style={{ color: "var(--muted)" }}
                data-testid={`programme-equipment-remove-${key}`}
              >
                <span aria-hidden="true">×</span>
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("equipmentNone")}</p>
      )}
      {takenAway.length ? (
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("equipmentTakenAway", { names: takenAway.map((key) => te(key)).join(", ") })}</p>
      ) : null}
      {addable.length ? (
        <div>
          <label htmlFor={addId} className="sr-only">{t("equipmentAdd")}</label>
          <Select
            id={addId}
            className={inputClass}
            style={inputStyle}
            value=""
            placeholder={t("equipmentAdd")}
            onValueChange={(value) => {
              if (value) onChange(addEquipment(derived, added, removed, value as EquipmentKey));
            }}
            data-testid="programme-equipment-add"
          >
            {addable.map((key) => <option key={key} value={key}>{te(key)}</option>)}
          </Select>
        </div>
      ) : null}
    </div>
  );
}
