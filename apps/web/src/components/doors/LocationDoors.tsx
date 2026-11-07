"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { DOOR_CATALOG_KEY, createDoor, deleteDoor, doorsKey, fetchDoorCatalog, fetchDoors, unlockDoor, updateDoor, type Door, type DoorProvider, type DoorRules } from "@/api/doors";
import { OpeningHoursEditor } from "@/components/admin/location/OpeningHoursEditor";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { Advanced, Field, INPUT_CLASS, OutlineButton, Pill, PrimaryButton, SecretOnce, TextButton, inputStyle, useIntegrationError, apiErrorCode } from "@/components/integrations/connections-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { Select } from "@/components/ui/Select";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { DOOR_WHO, RULE_RANGES, hoursToSpans, rangeError, rulesOf, spansToHours } from "./doors-model";

/**
 * Ρυθμίσεις › Παραρτήματα › <branch> › «Πόρτες» (W10 screen 4, option A;
 * ADR-381): the branch's doors with their controller and state, «Άνοιγμα»
 * from the desk, and each door's entry rules as three choices plus the
 * door's hours; minutes and seconds wait under «Προχωρημένα». Offline
 * means locked: the card says what members see and what to check.
 */
export function LocationDoors({ token, locationId }: { token: string; locationId: string }) {
  const t = useTranslations("Doors");
  const slug = useOrganizationSlug();
  const errorText = useIntegrationError();
  const queryClient = useQueryClient();
  const doors = useQuery({ queryKey: doorsKey(locationId), queryFn: () => fetchDoors(token, locationId) });
  const [adding, setAdding] = useState(false);
  const [rulesFor, setRulesFor] = useState<Door | null>(null);
  const [opened, setOpened] = useState<string | null>(null);
  const [removing, setRemoving] = useState<Door | null>(null);
  const refresh = () => void queryClient.invalidateQueries({ queryKey: doorsKey(locationId) });
  const unlock = useMutation({ mutationFn: (door: Door) => unlockDoor(token, door.id), onSuccess: (_ok, door) => setOpened(door.name), onError: refresh });
  const remove = useMutation({ mutationFn: (door: Door) => deleteDoor(token, door.id), onSettled: () => setRemoving(null), onSuccess: refresh });
  const toggle = useMutation({ mutationFn: (door: Door) => updateDoor(token, door.id, { status: door.status === "disabled" ? "active" : "disabled" }), onSuccess: refresh });

  return (
    <section aria-labelledby="location-doors" className="flex flex-col gap-3" data-testid="location-doors">
      <div className="flex items-center justify-between gap-3">
        <h2 id="location-doors" className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("title")}</h2>
        <OutlineButton onClick={() => setAdding(true)} data-testid="door-add">{t("add")}</OutlineButton>
      </div>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("hint")}</p>
      {doors.isError ? <ErrorNotice variant="field">{errorText(doors.error)}</ErrorNotice> : null}
      {doors.data?.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("empty")}</p> : null}

      {(doors.data ?? []).map((door) => {
        const rules = rulesOf(door.rules);
        const offline = door.status === "invalid" || Boolean(door.last_error);
        return (
          <div key={door.id} className="flex flex-col gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="door-row">
            <div className="flex flex-wrap items-center gap-3">
              <div className="min-w-0 flex-1">
                <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{door.name}</p>
                <p className="text-xs" style={{ color: "var(--dim)" }}>{[t(`provider.${door.provider}`), t(`who.${rules.who}.title`)].join(" · ")}</p>
              </div>
              <Pill tone={door.status === "disabled" ? "neutral" : offline ? "danger" : "success"}>
                {door.status === "disabled" ? t("statusOff") : offline ? t("statusOffline") : t("statusOnline")}
              </Pill>
              <OutlineButton disabled={unlock.isPending || door.status === "disabled"} onClick={() => unlock.mutate(door)} data-testid="door-unlock">{t("unlock")}</OutlineButton>
              <MoreMenu
                label={t("more")}
                items={[
                  { label: t("rules"), onSelect: () => setRulesFor(door) },
                  { label: door.status === "disabled" ? t("turnOn") : t("turnOff"), onSelect: () => toggle.mutate(door) },
                  { label: t("remove"), tone: "danger", onSelect: () => setRemoving(door) },
                ]}
              />
            </div>
            {offline && door.status !== "disabled" ? (
              <p className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)", color: "var(--text)" }} data-testid="door-offline">{t("offlineHint")}</p>
            ) : null}
            <button type="button" className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setRulesFor(door)}>{t("rulesSummary", { who: t(`who.${rules.who}.title`) })}</button>
          </div>
        );
      })}

      {opened ? <p role="status" className="text-sm" style={{ color: "var(--success)" }} data-testid="door-opened">{t("openedFromDesk", { door: opened })}</p> : null}
      {unlock.isError || remove.isError || toggle.isError ? <ErrorNotice variant="field">{errorText(unlock.error ?? remove.error ?? toggle.error)}</ErrorNotice> : null}
      <Link href={adminHref("/admin/check-in/access-log", slug)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("logLink")}</Link>

      {adding ? <NewDoorDialog token={token} locationId={locationId} onClose={() => { setAdding(false); refresh(); }} /> : null}
      {removing ? (
        <Dialog
          onClose={() => setRemoving(null)}
          title={t("removeQuestion", { door: removing.name })}
          size="sm"
          footer={
            <>
              <DialogButton tone="ghost" onClick={() => setRemoving(null)}>{t("cancel")}</DialogButton>
              <DialogButton tone="danger" disabled={remove.isPending} onClick={() => remove.mutate(removing)} testId="door-remove-confirm">{t("remove")}</DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("removeHint")}</p>
        </Dialog>
      ) : null}
      {rulesFor ? <RulesDialog token={token} door={rulesFor} onClose={() => { setRulesFor(null); refresh(); }} /> : null}
    </section>
  );
}

/** «+ Πόρτα»: name, controller and its key; the controller is checked before saving. */
function NewDoorDialog({ token, locationId, onClose }: { token: string; locationId: string; onClose: () => void }) {
  const t = useTranslations("Doors");
  const errorText = useIntegrationError();
  const catalog = useQuery({ queryKey: DOOR_CATALOG_KEY, queryFn: () => fetchDoorCatalog(token) });
  const providers = (catalog.data?.providers ?? ["shelly", "kisi"]) as DoorProvider[];
  const [name, setName] = useState("");
  const [provider, setProvider] = useState<DoorProvider>("shelly");
  const [server, setServer] = useState("");
  const [deviceId, setDeviceId] = useState("");
  const [lockId, setLockId] = useState("");
  const [secret, setSecret] = useState("");
  const [tried, setTried] = useState(false);
  const create = useMutation({
    mutationFn: () =>
      createDoor(token, {
        name: name.trim(),
        location_id: locationId,
        provider,
        settings: provider === "shelly" ? { server: server.trim(), device_id: deviceId.trim(), channel: 0 } : provider === "kisi" ? { lock_id: Number(lockId) } : {},
        credentials: provider === "shelly" ? { auth_key: secret.trim() } : provider === "kisi" ? { api_key: secret.trim() } : {},
      }),
  });
  const nameError = tried && !name.trim();
  const code = apiErrorCode(create.error);
  const settingsError = code === "invalid_door_settings" || code === "door_unauthorized" || code === "door_offline";

  return (
    <Dialog
      variant="sheet"
      size="lg"
      title={t("addTitle")}
      onClose={onClose}
      dismissible={!create.isPending}
      testId="door-dialog"
      footer={
        create.data ? (
          <div className="flex justify-end"><PrimaryButton onClick={onClose}>{t("done")}</PrimaryButton></div>
        ) : (
          <div className="flex flex-wrap justify-end gap-2">
            <TextButton onClick={onClose}>{t("cancel")}</TextButton>
            <PrimaryButton
              disabled={create.isPending}
              onClick={() => {
                setTried(true);
                if (name.trim()) create.mutate();
              }}
              data-testid="door-create"
            >
              {t("checkAndSave")}
            </PrimaryButton>
          </div>
        )
      }
    >
      {create.data ? (
        <div className="space-y-3">
          <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("added", { door: create.data.door.name })}</p>
          <Advanced>
            <SecretOnce title={t("eventUrlTitle")} secret={create.data.event_url} hint={t("eventUrlHint")} />
          </Advanced>
        </div>
      ) : (
        <div className="space-y-4">
          <Field id="door-name" label={t("name")} error={nameError ? t("nameRequired") : null}>
            <input id="door-name" value={name} maxLength={80} placeholder={t("namePlaceholder")} aria-invalid={nameError} onChange={(event) => setName(event.target.value)} className={INPUT_CLASS} style={inputStyle(nameError)} />
          </Field>
          <Field id="door-provider" label={t("controller")} hint={t(`providerHint.${provider}`)}>
            <Select id="door-provider" aria-label={t("controller")} value={provider} onValueChange={(value: string) => setProvider(value as DoorProvider)}>
              {providers.map((item) => <option key={item} value={item}>{t(`provider.${item}`)}</option>)}
            </Select>
          </Field>
          {provider === "shelly" ? (
            <>
              <Field id="door-server" label={t("shellyServer")} hint={t("shellyServerHint")}>
                <input id="door-server" value={server} onChange={(event) => setServer(event.target.value)} className={INPUT_CLASS} style={inputStyle(settingsError)} />
              </Field>
              <Field id="door-device" label={t("shellyDevice")}>
                <input id="door-device" value={deviceId} onChange={(event) => setDeviceId(event.target.value)} className={INPUT_CLASS} style={inputStyle(settingsError)} />
              </Field>
            </>
          ) : null}
          {provider === "kisi" ? (
            <Field id="door-lock" label={t("kisiLock")}>
              <input id="door-lock" inputMode="numeric" value={lockId} onChange={(event) => setLockId(event.target.value.replace(/\D/g, ""))} className={INPUT_CLASS} style={inputStyle(settingsError)} />
            </Field>
          ) : null}
          {provider !== "sandbox" ? (
            <Field id="door-key" label={t("controllerKey")} hint={t("controllerKeyHint")} error={settingsError ? t(`errors.${code}`) : null}>
              <input id="door-key" type="password" autoComplete="off" value={secret} onChange={(event) => setSecret(event.target.value)} className={INPUT_CLASS} style={inputStyle(settingsError)} />
            </Field>
          ) : null}
          {create.isError && !settingsError ? <ErrorNotice variant="field">{errorText(create.error)}</ErrorNotice> : null}
        </div>
      )}
    </Dialog>
  );
}

/** «Κανόνες εισόδου»: who (three choices), the door's hours, and «Προχωρημένα». */
function RulesDialog({ token, door, onClose }: { token: string; door: Door; onClose: () => void }) {
  const t = useTranslations("Doors");
  const errorText = useIntegrationError();
  const [rules, setRules] = useState<DoorRules>(() => rulesOf(door.rules));
  const [hoursOn, setHoursOn] = useState(rules.hours.length > 0);
  const save = useMutation({ mutationFn: () => updateDoor(token, door.id, { rules: { ...rules, hours: hoursOn ? rules.hours : [] } }), onSuccess: onClose });
  const numbers = (["window_before_minutes", "window_after_minutes", "unlock_seconds"] as const).map((key) => ({ key, error: rangeError(key, rules[key]) }));
  const invalid = numbers.some((item) => item.error) || (hoursOn && rules.hours.length === 0);

  return (
    <Dialog
      variant="panel"
      size="lg"
      title={t("rulesTitle", { door: door.name })}
      description={t("staffAlwaysNote")}
      onClose={onClose}
      dismissible={!save.isPending}
      testId="door-rules"
      footer={
        <div className="flex flex-wrap justify-end gap-2">
          <TextButton onClick={onClose}>{t("cancel")}</TextButton>
          <PrimaryButton disabled={save.isPending || invalid} onClick={() => save.mutate()} data-testid="door-rules-save">{t("saveRules")}</PrimaryButton>
        </div>
      }
    >
      <div className="space-y-4">
        <div role="radiogroup" aria-label={t("whoLabel")} className="space-y-2">
          {DOOR_WHO.map((who) => (
            <button
              key={who}
              type="button"
              role="radio"
              aria-checked={rules.who === who}
              onClick={() => setRules({ ...rules, who })}
              className="flex w-full flex-col items-start rounded-2xl px-4 py-3 text-start"
              style={{ background: "var(--panel)", border: `1px solid ${rules.who === who ? "var(--primary)" : "var(--border)"}` }}
            >
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(`who.${who}.title`)}</span>
              <span className="text-xs leading-5" style={{ color: "var(--dim)" }}>
                {t(`who.${who}.hint`, { before: rules.window_before_minutes, after: rules.window_after_minutes })}
              </span>
            </button>
          ))}
        </div>

        <div className="space-y-2">
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("hours")}</p>
              <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hoursOn ? t("hoursOnHint") : t("hoursOffHint")}</p>
            </div>
            <Toggle label={t("hours")} checked={hoursOn} onChange={setHoursOn} />
          </div>
          {hoursOn ? (
            <OpeningHoursEditor value={hoursToSpans(rules.hours)} onChange={(spans) => setRules({ ...rules, hours: spansToHours(spans) })} />
          ) : null}
          {hoursOn && rules.hours.length === 0 ? <p className="text-xs" style={{ color: "var(--danger-strong)" }}>{t("hoursRequired")}</p> : null}
        </div>

        <Advanced>
          {numbers.map(({ key, error }) => (
            <Field key={key} id={`door-${key}`} label={t(`advanced.${key}`)} error={error ? t("rangeError", { min: error.min, max: error.max }) : null}>
              <input
                id={`door-${key}`}
                inputMode="numeric"
                value={String(rules[key])}
                aria-invalid={Boolean(error)}
                onChange={(event) => setRules({ ...rules, [key]: Number(event.target.value.replace(/\D/g, "") || "0") })}
                className={`${INPUT_CLASS} max-w-[8rem]`}
                style={inputStyle(Boolean(error))}
                max={RULE_RANGES[key][1]}
              />
            </Field>
          ))}
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("staffAlways")}</p>
              <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("staffAlwaysHint")}</p>
            </div>
            <Toggle label={t("staffAlways")} checked={rules.staff_always} onChange={(staff_always) => setRules({ ...rules, staff_always })} />
          </div>
        </Advanced>
        {save.isError ? <ErrorNotice variant="field">{errorText(save.error)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
