"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { API_KEYS_KEY, createApiKey, fetchApiKeys, revokeApiKey, rotateApiKey, type ApiKey, type ApiKeyWithToken } from "@/api/integrations";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { KEY_PURPOSES, PURPOSE_SCOPES, SCOPE_OBJECTS, keyLabel, scopesOf, toggleScope, type KeyPurpose, type Scope } from "./connections-model";
import { Card, CardTitle, Field, INPUT_CLASS, Pill, PrimaryButton, SecretOnce, TextButton, inputStyle, useIntegrationError, useWhen } from "./connections-ui";

/**
 * Ρυθμίσεις › Συνδέσεις › Κλειδιά API (W10 screen 1, option B; ADR-378).
 * The list of the box's keys, and «Νέο κλειδί» as a three-step guide:
 * what it is for → the fewest rights that purpose needs (changeable with
 * a tap) → the key, shown once, with what to do next in Zapier.
 */
export function ApiKeysSettings({ token }: { token: string }) {
  const t = useTranslations("Connections");
  const queryClient = useQueryClient();
  const errorText = useIntegrationError();
  const keys = useQuery({ queryKey: API_KEYS_KEY, queryFn: () => fetchApiKeys(token) });
  const [creating, setCreating] = useState(false);
  const [rotated, setRotated] = useState<ApiKeyWithToken | null>(null);

  const refresh = () => void queryClient.invalidateQueries({ queryKey: API_KEYS_KEY });
  const rotate = useMutation({ mutationFn: (id: string) => rotateApiKey(token, id), onSuccess: (data) => { setRotated(data); refresh(); } });
  const revoke = useMutation({ mutationFn: (id: string) => revokeApiKey(token, id), onSuccess: refresh });

  const active = (keys.data ?? []).filter((key) => key.status === "active");

  return (
    <Card testId="api-keys">
      <CardTitle title={t("keysTitle")} hint={t("keysHint")}>
        <PrimaryButton onClick={() => setCreating(true)} data-testid="api-key-new">{t("keyNew")}</PrimaryButton>
      </CardTitle>
      {keys.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {keys.isError ? <ErrorNotice variant="field">{errorText(keys.error)}</ErrorNotice> : null}
      {keys.data && active.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("keysEmpty")}</p> : null}
      {rotated ? <SecretOnce title={t("keyCopyNow")} secret={rotated.token} hint={t("keyRotatedHint")} testId="api-key-rotated" /> : null}
      <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
        {active.map((key) => (
          <KeyRow
            key={key.id}
            apiKey={key}
            pending={rotate.isPending || revoke.isPending}
            onRotate={() => rotate.mutate(key.id)}
            onRevoke={() => revoke.mutate(key.id)}
          />
        ))}
      </ul>
      {rotate.isError || revoke.isError ? <ErrorNotice variant="field">{errorText(rotate.error ?? revoke.error)}</ErrorNotice> : null}
      {creating ? <NewKeyGuide token={token} onClose={() => { setCreating(false); refresh(); }} /> : null}
    </Card>
  );
}

function KeyRow({ apiKey, pending, onRotate, onRevoke }: { apiKey: ApiKey; pending: boolean; onRotate: () => void; onRevoke: () => void }) {
  const t = useTranslations("Connections");
  const locale = useUiLocale();
  const when = useWhen();
  return (
    <li className="flex flex-wrap items-start gap-3 py-3" style={{ borderColor: "var(--border)" }} data-testid="api-key-row">
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{apiKey.name}</p>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
          <span className="font-mono">{keyLabel(apiKey)}</span>
          {" · "}
          {apiKey.scopes.map((scope) => t(`scope.${scope.replace(":", "_")}`)).join(" · ")}
        </p>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("keyLastUsed", { when: when(apiKey.last_used_at, locale) })}</p>
      </div>
      <Pill tone="success">{t("keyActive")}</Pill>
      <div className="flex flex-wrap gap-2">
        <ConfirmButton label={t("keyRotate")} question={t("keyRotateQuestion")} confirmLabel={t("keyRotate")} pending={pending} onConfirm={onRotate} />
        <ConfirmButton label={t("keyRevoke")} question={t("keyRevokeQuestion")} confirmLabel={t("keyRevoke")} pending={pending} onConfirm={onRevoke} />
      </div>
    </li>
  );
}

/** «Νέο κλειδί API»: Για τι το θέλεις; → Τι θα μπορεί να κάνει → το κλειδί μία φορά. */
function NewKeyGuide({ token, onClose }: { token: string; onClose: () => void }) {
  const t = useTranslations("Connections");
  const errorText = useIntegrationError();
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [purpose, setPurpose] = useState<KeyPurpose>("zapier");
  const [name, setName] = useState("");
  const [scopes, setScopes] = useState<string[]>(PURPOSE_SCOPES.zapier);
  const [nameMissing, setNameMissing] = useState(false);
  const create = useMutation({ mutationFn: () => createApiKey(token, { name: name.trim(), scopes }), onSuccess: () => setStep(3) });

  const choose = (next: KeyPurpose) => {
    setPurpose(next);
    setScopes(PURPOSE_SCOPES[next]);
  };
  const submit = () => {
    if (!name.trim()) {
      setNameMissing(true);
      return;
    }
    create.mutate();
  };

  const footer =
    step === 1 ? (
      <div className="flex justify-end gap-2">
        <TextButton onClick={onClose}>{t("cancel")}</TextButton>
        <PrimaryButton onClick={() => { setName((value) => value || t(`purpose.${purpose}.name`)); setStep(2); }} data-testid="api-key-continue">{t("continue")}</PrimaryButton>
      </div>
    ) : step === 2 ? (
      <div className="flex justify-end gap-2">
        <TextButton onClick={() => setStep(1)}>{t("back")}</TextButton>
        <PrimaryButton disabled={create.isPending || scopes.length === 0} onClick={submit} data-testid="api-key-create">{t("keyCreate")}</PrimaryButton>
      </div>
    ) : (
      <div className="flex justify-end">
        <PrimaryButton onClick={onClose}>{t("done")}</PrimaryButton>
      </div>
    );

  return (
    <Dialog variant="sheet" size="lg" title={t("keyNewTitle")} eyebrow={t("stepOf", { step, total: 3 })} onClose={onClose} dismissible={!create.isPending} footer={footer} testId="api-key-guide">
      {step === 1 ? (
        <div role="radiogroup" aria-label={t("purposeQuestion")} className="space-y-2">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("purposeQuestion")}</p>
          {KEY_PURPOSES.map((item) => (
            <button
              key={item}
              type="button"
              role="radio"
              aria-checked={purpose === item}
              onClick={() => choose(item)}
              className="flex w-full flex-col items-start rounded-2xl px-4 py-3 text-start"
              style={{ background: "var(--panel)", border: `1px solid ${purpose === item ? "var(--primary)" : "var(--border)"}` }}
            >
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(`purpose.${item}.title`)}</span>
              <span className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t(`purpose.${item}.hint`)}</span>
            </button>
          ))}
        </div>
      ) : null}

      {step === 2 ? (
        <div className="space-y-4">
          <Field id="api-key-name" label={t("keyName")} error={nameMissing ? t("errors.invalid_api_key_name") : null}>
            <input
              id="api-key-name"
              value={name}
              maxLength={80}
              aria-invalid={nameMissing}
              onChange={(event) => { setName(event.target.value); setNameMissing(false); }}
              className={INPUT_CLASS}
              style={inputStyle(nameMissing)}
            />
          </Field>
          <div className="space-y-2">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("keyScopes")}</p>
            <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("keyScopesHint", { purpose: t(`purpose.${purpose}.title`) })}</p>
            <ScopeGrid scopes={scopes} onToggle={(scope) => setScopes((current) => toggleScope(current, scope))} />
            {scopes.length === 0 ? <ErrorNotice variant="field">{t("errors.invalid_scopes")}</ErrorNotice> : null}
          </div>
          <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>{t("keyActsForYou")}</p>
          {create.isError ? <ErrorNotice variant="field">{errorText(create.error)}</ErrorNotice> : null}
        </div>
      ) : null}

      {step === 3 && create.data ? (
        <div className="space-y-3">
          <SecretOnce title={t("keyCopyNow")} secret={create.data.token} hint={t("keyOnceHint")} testId="api-key-token" />
          {purpose === "zapier" ? (
            <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("zapierNextTitle")}</p>
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("zapierNextHint")}</p>
            </div>
          ) : null}
        </div>
      ) : null}
    </Dialog>
  );
}

/** One row per object, «Ανάγνωση» and «Αλλαγές» as chips (payments: read only). */
function ScopeGrid({ scopes, onToggle }: { scopes: string[]; onToggle: (scope: Scope) => void }) {
  const t = useTranslations("Connections");
  return (
    <ul className="divide-y rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)", borderColor: "var(--border)" }}>
      {SCOPE_OBJECTS.map((object) => (
        <li key={object} className="flex flex-wrap items-center gap-2 px-4 py-2" style={{ borderColor: "var(--border)" }}>
          <span className="min-w-0 flex-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`object.${object}`)}</span>
          {scopesOf(object).map((scope) => {
            const on = scopes.includes(scope);
            return (
              <button
                key={scope}
                type="button"
                aria-pressed={on}
                title={t(`scope.${scope.replace(":", "_")}`)}
                onClick={() => onToggle(scope)}
                className="min-h-9 rounded-xl px-3 text-xs font-semibold"
                style={on ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" } : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
                data-testid={`scope-${scope}`}
              >
                {scope.endsWith(":read") ? t("accessRead") : object === "webhooks" ? t("accessSubscribe") : t("accessWrite")}
              </button>
            );
          })}
        </li>
      ))}
    </ul>
  );
}
