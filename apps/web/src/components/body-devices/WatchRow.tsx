"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchWatches,
  saveWatchSettings,
  unpairWatch,
  WATCHES_KEY,
  type PairedWatch,
  type WatchList,
  type WatchSettings,
} from "@/api/body-devices";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { IntegerInput } from "@/components/integer-input";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * «Ρολόι» in Εγώ › Συνδεδεμένες συσκευές (ADR-375, mockup d8pair A): one
 * more row next to Garmin and the phone's health app. The phone app pairs a
 * watch by itself when it finds one (the question comes when a WOD opens,
 * ANR's D8 rules); here the person sees it and changes what it shows.
 */
export function WatchRows({ token }: { token: string }) {
  const t = useTranslations("BodyDevices");
  const watches = useQuery({ queryKey: WATCHES_KEY, enabled: Boolean(token), queryFn: () => fetchWatches(token), retry: false });
  const [open, setOpen] = useState<PairedWatch | null>(null);
  if (!watches.data) return null;

  if (watches.data.watches.length === 0) {
    return (
      <li
        data-testid="watch-row"
        className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
      >
        <span className="flex min-w-0 flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("watch.title")}</span>
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("watch.fromPhone")}</span>
        </span>
      </li>
    );
  }

  return (
    <>
      {watches.data.watches.map((watch) => (
        <li key={watch.platform} data-testid="watch-row">
          <button
            type="button"
            onClick={() => setOpen(watch)}
            className="flex w-full items-center justify-between gap-3 rounded-2xl px-4 py-3 text-left"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
          >
            <span className="flex min-w-0 flex-col">
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("watch.title")}</span>
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("watch.shows")}</span>
            </span>
            <span className="shrink-0 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {watch.device_name ?? t(`watch.platform.${watch.platform}`)}
            </span>
          </button>
        </li>
      ))}
      {open ? <WatchSettingsSheet token={token} watch={open} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

function WatchSettingsSheet({ token, watch, onClose }: { token: string; watch: PairedWatch; onClose: () => void }) {
  const t = useTranslations("BodyDevices");
  const queryClient = useQueryClient();
  const [settings, setSettings] = useState<WatchSettings>(watch.settings);
  const [advanced, setAdvanced] = useState(false);
  const [maxHr, setMaxHr] = useState<number | null>(watch.settings.max_hr ?? null);
  const maxHrInvalid = maxHr !== null && (maxHr < 120 || maxHr > 230);

  const replace = (saved: PairedWatch | null) =>
    queryClient.setQueryData<WatchList>(WATCHES_KEY, (current) =>
      current
        ? {
            ...current,
            watches: saved
              ? current.watches.map((entry) => (entry.platform === saved.platform ? saved : entry))
              : current.watches.filter((entry) => entry.platform !== watch.platform),
          }
        : current,
    );

  const save = useMutation({
    mutationFn: (change: Partial<WatchSettings>) => saveWatchSettings(token, watch, change),
    onSuccess: (saved) => {
      setSettings(saved.settings);
      replace(saved);
    },
  });
  const unpair = useMutation({
    mutationFn: () => unpairWatch(token, watch.platform),
    onSuccess: () => {
      replace(null);
      onClose();
    },
  });

  function toggle(key: "show_heart_rate" | "show_pace" | "haptics", value: boolean) {
    setSettings((current) => ({ ...current, [key]: value }));
    save.mutate({ [key]: value });
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("watch.title")}
      description={watch.device_name ?? t(`watch.platform.${watch.platform}`)}
      titleId="watch-settings"
      variant="sheet"
      size="md"
      testId="watch-settings"
    >
      <div className="flex flex-col gap-2">
        <Switch
          checked={settings.show_heart_rate ?? true}
          onChange={(value) => toggle("show_heart_rate", value)}
          label={t("watch.heartRate")}
          hint={t("watch.heartRateHint")}
        />
        <Switch checked={settings.show_pace ?? true} onChange={(value) => toggle("show_pace", value)} label={t("watch.pace")} />
        <Switch checked={settings.haptics ?? true} onChange={(value) => toggle("haptics", value)} label={t("watch.haptics")} />
        {watch.needs_upgrade ? <p className="text-xs" style={{ color: "var(--warning)" }}>{t("watch.needsUpgrade")}</p> : null}
        <button
          type="button"
          aria-expanded={advanced}
          onClick={() => setAdvanced(!advanced)}
          className="self-start text-sm font-semibold"
          style={{ color: "var(--dim)" }}
        >
          {t("advanced")}
        </button>
        {advanced ? (
          <div className="flex flex-col gap-3">
            <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("watch.maxHr")}
              <IntegerInput
                value={maxHr}
                onValueChange={setMaxHr}
                min={120}
                max={230}
                aria-invalid={maxHrInvalid}
                onBlur={() => {
                  if (!maxHrInvalid && maxHr !== (settings.max_hr ?? null)) save.mutate({ max_hr: maxHr });
                }}
                className="min-h-11 rounded-2xl px-4"
                style={{
                  background: "var(--panel-muted)",
                  border: `1px solid ${maxHrInvalid ? "var(--danger)" : "var(--border)"}`,
                  color: "var(--text)",
                }}
              />
              <span className="text-xs font-normal" style={{ color: maxHrInvalid ? "var(--danger)" : "var(--dim)" }}>
                {maxHrInvalid ? t("watch.maxHrInvalid") : t("watch.maxHrHint")}
              </span>
            </label>
            <ConfirmButton
              label={t("watch.unpair")}
              question={t("watch.unpairConfirm")}
              confirmLabel={t("watch.unpairAction")}
              pending={unpair.isPending}
              onConfirm={() => unpair.mutate()}
              testId="watch-unpair"
            />
          </div>
        ) : null}
        {save.isError || unpair.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
