"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchAdminSettings, updateAdminSettings, type AdminSettingsPayload } from "@/api/settings";
import { listWorkoutKinds, mergeWorkoutKind, updateWorkoutKind, WOD_ASSISTANT_AVAILABILITY_KEY, WORKOUT_KINDS_KEY } from "@/api/workouts";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { InlineConfirm } from "@/components/ui/InlineConfirm";
import { Select } from "@/components/ui/Select";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { workoutFamilyColor } from "@/lib/theme";
import type { BoxWorkoutKind, WorkoutKindCatalogue } from "@/lib/workout-kinds";
import { WORKOUT_TYPE_FAMILIES, WORKOUT_TYPES, type WorkoutType, type WorkoutTypeFamily } from "@/lib/workout-types";

const SETTINGS_KEY = ["admin", "settings"] as const;

/**
 * ADR-275: which workout kinds the gym's editors offer. Every kind is on
 * until the gym turns some off; at least one stays on. A workout keeps its
 * kind when the gym later hides it.
 */
export function WorkoutTypesSetting({ token }: { token: string }) {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const labels = useWorkoutTypeLabels();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: SETTINGS_KEY, queryFn: () => fetchAdminSettings(token) });
  const save = useMutation({
    mutationFn: (types: WorkoutType[] | null) => updateAdminSettings(token, { workouts: { workout_types: types } }),
    onSuccess: (data) => {
      queryClient.setQueryData<AdminSettingsPayload>(SETTINGS_KEY, data);
      void queryClient.invalidateQueries({ queryKey: WOD_ASSISTANT_AVAILABILITY_KEY });
    },
  });
  if (!settings.data) return null;

  const stored = save.isPending ? save.variables : settings.data.workouts?.workout_types;
  const offered = new Set<string>(stored && stored.length > 0 ? stored : WORKOUT_TYPES);

  function toggle(type: WorkoutType) {
    const next = new Set(offered);
    if (next.has(type)) next.delete(type);
    else next.add(type);
    if (next.size === 0) return;
    const chosen = WORKOUT_TYPES.filter((item) => next.has(item));
    // Every kind on is stored as "no choice", so kinds added later show up too.
    save.mutate(chosen.length === WORKOUT_TYPES.length ? null : chosen);
  }

  return (
    <div className="space-y-4" data-testid="workout-types-setting">
      <BoxWorkoutTypesSetting token={token} />
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("setting.hint")}
      </p>
      {WORKOUT_TYPE_FAMILIES.map((group) => (
        <fieldset key={group.family} className="space-y-2">
          <legend className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>
            {labels.family(group.family)}
          </legend>
          <div className="flex flex-wrap gap-2">
            {group.types.map((type) => {
              const on = offered.has(type);
              return (
                <button
                  key={type}
                  type="button"
                  aria-pressed={on}
                  disabled={save.isPending || (on && offered.size === 1)}
                  onClick={() => toggle(type)}
                  className="min-h-9 rounded-full border px-3 text-sm font-semibold disabled:opacity-60"
                  style={{
                    borderColor: on ? "var(--primary)" : "var(--border)",
                    background: on ? "color-mix(in srgb, var(--primary) 12%, var(--card))" : "var(--card)",
                    color: on ? "var(--text)" : "var(--muted)",
                  }}
                >
                  {labels.type(type)}
                </button>
              );
            })}
          </div>
        </fieldset>
      ))}
      {save.error ? <ErrorNotice>{localizeError(save.error, i18n)}</ErrorNotice> : null}
    </div>
  );
}

/**
 * ADR-690: the box's own workout types (made from the WOD editor). Owners
 * and admins rename one, change its family, hide it from the editors, or
 * merge it into another type (the box's WODs move to that type).
 */
export function BoxWorkoutTypesSetting({ token }: { token: string }) {
  const t = useTranslations("WorkoutTypes");
  const queryClient = useQueryClient();
  const kinds = useQuery({ queryKey: WORKOUT_KINDS_KEY, queryFn: () => listWorkoutKinds(token) });
  const own = (kinds.data?.box ?? []).filter((kind) => kind.status !== "merged");
  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: WORKOUT_KINDS_KEY }),
      queryClient.invalidateQueries({ queryKey: WOD_ASSISTANT_AVAILABILITY_KEY }),
    ]);

  return (
    <section className="space-y-3" data-testid="box-workout-types">
      <div>
        <h3 className="text-sm font-bold">{t("box.title")}</h3>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {own.length > 0 ? t("box.hint") : t("box.empty")}
        </p>
      </div>
      {own.length > 0 ? (
        <ul className="space-y-2">
          {own.map((kind) => (
            <BoxWorkoutTypeRow key={kind.id} token={token} kind={kind} catalogue={kinds.data!} onChanged={refresh} />
          ))}
        </ul>
      ) : null}
    </section>
  );
}

function BoxWorkoutTypeRow({
  token,
  kind,
  catalogue,
  onChanged,
}: {
  token: string;
  kind: BoxWorkoutKind;
  catalogue: WorkoutKindCatalogue;
  onChanged: () => Promise<unknown>;
}) {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const labels = useWorkoutTypeLabels();
  const [label, setLabel] = useState(kind.label);
  const [merging, setMerging] = useState(false);
  const [target, setTarget] = useState("");
  const update = useMutation({
    mutationFn: (body: { label?: string; family?: WorkoutTypeFamily; hidden?: boolean }) => updateWorkoutKind(token, kind.id, body),
    onSuccess: onChanged,
  });
  const merge = useMutation({
    mutationFn: () => mergeWorkoutKind(token, kind.id, target),
    onSuccess: async () => {
      setMerging(false);
      await onChanged();
    },
  });
  const hidden = kind.status === "hidden";
  const targets = [
    ...WORKOUT_TYPE_FAMILIES.flatMap((group) => group.types.map((type) => ({ ref: type as string, family: group.family as WorkoutTypeFamily }))),
    ...catalogue.additions.map((addition) => ({ ref: addition.key, family: addition.family })),
    ...catalogue.box.filter((other) => other.status === "active" && other.id !== kind.id).map((other) => ({ ref: other.ref, family: other.family })),
  ];
  const error = update.error ?? merge.error;

  return (
    <li className="space-y-2 rounded-2xl border p-3" style={{ borderColor: "var(--border)", background: "var(--card)", opacity: hidden ? 0.75 : 1 }} data-testid="box-workout-type">
      <div className="flex flex-wrap items-center gap-2">
        <input
          value={label}
          maxLength={40}
          onChange={(event) => setLabel(event.target.value)}
          onBlur={() => {
            if (label.trim() && label.trim() !== kind.label) update.mutate({ label: label.trim() });
            else setLabel(kind.label);
          }}
          aria-label={t("box.rename")}
          className="min-h-10 min-w-40 flex-1 rounded-xl border px-3 text-sm font-semibold"
          style={{ borderColor: "var(--border)", background: "var(--bg)", color: "var(--text)" }}
        />
        <Select
          value={kind.family}
          onValueChange={(family) => update.mutate({ family: family as WorkoutTypeFamily })}
          aria-label={t("box.family")}
          className="min-h-10 rounded-xl border px-3 text-sm"
          style={{ borderColor: workoutFamilyColor(kind.family), background: "var(--bg)", color: "var(--text)" }}
        >
          {WORKOUT_TYPE_FAMILIES.map((group) => (
            <option key={group.family} value={group.family}>
              {labels.family(group.family)}
            </option>
          ))}
        </Select>
      </div>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <button
          type="button"
          className="min-h-9 rounded-full border px-3 font-semibold"
          style={{ borderColor: "var(--border)", color: "var(--muted)" }}
          disabled={update.isPending}
          onClick={() => update.mutate({ hidden: !hidden })}
        >
          {hidden ? t("box.show") : t("box.hide")}
        </button>
        <button
          type="button"
          className="min-h-9 rounded-full border px-3 font-semibold"
          style={{ borderColor: "var(--border)", color: "var(--muted)" }}
          onClick={() => setMerging((open) => !open)}
          aria-expanded={merging}
        >
          {t("box.merge")}
        </button>
        {hidden ? <span style={{ color: "var(--dim)" }}>{t("box.hiddenNote")}</span> : null}
      </div>
      {merging ? (
        <div className="space-y-2">
          <Select
            value={target}
            onValueChange={setTarget}
            placeholder={t("box.mergeInto")}
            aria-label={t("box.mergeInto")}
            className="min-h-10 w-full rounded-xl border px-3 text-sm"
            style={{ borderColor: "var(--border)", background: "var(--bg)", color: "var(--text)" }}
          >
            {WORKOUT_TYPE_FAMILIES.map((group) => (
              <optgroup key={group.family} label={labels.family(group.family)}>
                {targets
                  .filter((item) => item.family === group.family)
                  .map((item) => (
                    <option key={item.ref} value={item.ref}>
                      {item.ref.startsWith("box:") ? catalogue.box.find((other) => other.ref === item.ref)?.label : labels.type(item.ref)}
                    </option>
                  ))}
              </optgroup>
            ))}
          </Select>
          {target ? (
            <InlineConfirm
              tone="primary"
              question={t("box.mergeQuestion", { name: kind.label })}
              cancelLabel={t("create.cancel")}
              confirmLabel={t("box.mergeConfirm")}
              busy={merge.isPending}
              onCancel={() => {
                setTarget("");
                setMerging(false);
              }}
              onConfirm={() => merge.mutate()}
            />
          ) : null}
        </div>
      ) : null}
      {error ? <ErrorNotice>{localizeError(error, i18n)}</ErrorNotice> : null}
    </li>
  );
}
