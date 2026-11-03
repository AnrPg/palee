"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  EMAIL_LIST_KEY,
  deleteEmailList,
  fetchEmailList,
  rotateUnsubscribeUrl,
  saveEmailList,
  syncEmailList,
  type AudienceConnection,
  type AudienceProvider,
} from "@/api/integrations";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";

import {
  Advanced,
  Card,
  CardTitle,
  Field,
  INPUT_CLASS,
  OutlineButton,
  Pill,
  PrimaryButton,
  SecretOnce,
  TextButton,
  apiErrorCode,
  inputStyle,
  useIntegrationError,
  useWhen,
} from "./connections-ui";

const PROVIDERS: AudienceProvider[] = ["mailchimp", "brevo"];

/**
 * Ρυθμίσεις › Συνδέσεις › Λίστα email (W10 screen 3, option A; ADR-380):
 * connect Mailchimp or Brevo with a key and a list. Only members who said
 * yes are sent, with email and first name; anyone who stops, leaves or
 * deletes their account is unsubscribed, never deleted. The member's own
 * switch lives in Box › Ειδοποιήσεις, next to the SMS switches.
 */
export function EmailListSettings({ token }: { token: string }) {
  const t = useTranslations("Connections");
  const locale = useUiLocale();
  const when = useWhen();
  const errorText = useIntegrationError();
  const queryClient = useQueryClient();
  const list = useQuery({ queryKey: EMAIL_LIST_KEY, queryFn: () => fetchEmailList(token) });
  const [editing, setEditing] = useState(false);
  const set = (connection: AudienceConnection | null) => queryClient.setQueryData(EMAIL_LIST_KEY, connection);
  const sync = useMutation({ mutationFn: () => syncEmailList(token) });
  const remove = useMutation({ mutationFn: () => deleteEmailList(token), onSuccess: () => set(null) });

  if (list.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (list.isError) return <ErrorNotice variant="field">{errorText(list.error)}</ErrorNotice>;
  const connection = list.data ?? null;

  return (
    <Card testId="email-list">
      <CardTitle
        title={connection ? t("listTitleWith", { provider: t(`provider.${connection.provider}`) }) : t("listTitle")}
        hint={connection ? t("listSummary", { list: connection.list_id }) : t("listHint")}
      >
        {connection ? <Pill tone={connection.status === "active" ? "success" : "danger"}>{connection.status === "active" ? t("listConnected") : t("listProblem")}</Pill> : null}
      </CardTitle>

      <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>{t("listRules")}</p>

      {connection && !editing ? (
        <>
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {t("listLastSync", { when: when(connection.last_synced_at, locale) })}
          </p>
          {connection.last_error ? <ErrorNotice variant="field">{t("listLastError")}</ErrorNotice> : null}
          <div className="flex flex-wrap gap-2">
            <OutlineButton disabled={sync.isPending} onClick={() => sync.mutate()} data-testid="email-list-sync">{t("listSyncNow")}</OutlineButton>
            <OutlineButton onClick={() => setEditing(true)}>{t("listChangeKey")}</OutlineButton>
            <ConfirmButton label={t("listDisconnect")} question={t("listDisconnectQuestion")} confirmLabel={t("listDisconnect")} pending={remove.isPending} onConfirm={() => remove.mutate()} />
          </div>
          {sync.isSuccess ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("listSyncQueued")}</p> : null}
          {sync.isError || remove.isError ? <ErrorNotice variant="field">{errorText(sync.error ?? remove.error)}</ErrorNotice> : null}
          <Advanced testId="email-list-advanced">
            <UnsubscribeHook token={token} connection={connection} onMade={() => set({ ...connection, unsubscribe_hook: true })} />
          </Advanced>
        </>
      ) : (
        <ConnectForm
          token={token}
          connection={connection}
          onSaved={(saved) => {
            set(saved);
            setEditing(false);
          }}
          onCancel={connection ? () => setEditing(false) : undefined}
        />
      )}
      {/* W10 screen 3, question 3: the box names its list provider in its own privacy notice. */}
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("listPrivacyReminder")}</p>
    </Card>
  );
}

/**
 * «Διαγραφές από τη λίστα» (ADR-380, 2026-11-03): the address the box pastes
 * into Mailchimp or Brevo, so someone who unsubscribes there has their
 * switch in Palee turned off too. Shown once; a new one replaces it.
 */
function UnsubscribeHook({ token, connection, onMade }: { token: string; connection: AudienceConnection; onMade: () => void }) {
  const t = useTranslations("Connections");
  const errorText = useIntegrationError();
  const make = useMutation({ mutationFn: () => rotateUnsubscribeUrl(token), onSuccess: onMade });
  const provider = connection.provider === "brevo" ? "brevo" : "mailchimp";
  return (
    <div className="space-y-3" data-testid="email-list-unsubscribe">
      <div className="flex flex-wrap items-center gap-2">
        <p className="min-w-0 flex-1 text-sm font-bold" style={{ color: "var(--text)" }}>{t("unsubscribeTitle")}</p>
        <Pill tone={connection.unsubscribe_hook ? "success" : "neutral"}>{connection.unsubscribe_hook ? t("unsubscribeOn") : t("unsubscribeOff")}</Pill>
      </div>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("unsubscribeHint")}</p>
      {make.data ? (
        <SecretOnce title={t("unsubscribeUrlTitle")} secret={make.data.url} hint={t(`unsubscribeWhere.${provider}`)} testId="email-list-unsubscribe-url" />
      ) : (
        <OutlineButton disabled={make.isPending} onClick={() => make.mutate()} data-testid="email-list-unsubscribe-make">
          {connection.unsubscribe_hook ? t("unsubscribeRenew") : t("unsubscribeMake")}
        </OutlineButton>
      )}
      {connection.unsubscribe_hook && !make.data ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("unsubscribeRenewHint")}</p> : null}
      {make.isError ? <ErrorNotice variant="field">{errorText(make.error)}</ErrorNotice> : null}
    </div>
  );
}

function ConnectForm({ token, connection, onSaved, onCancel }: { token: string; connection: AudienceConnection | null; onSaved: (connection: AudienceConnection | null) => void; onCancel?: () => void }) {
  const t = useTranslations("Connections");
  const errorText = useIntegrationError();
  const [provider, setProvider] = useState<AudienceProvider>(connection?.provider && connection.provider !== "sandbox" ? connection.provider : "mailchimp");
  const [apiKey, setApiKey] = useState("");
  const [listId, setListId] = useState(connection?.list_id ?? "");
  const [tried, setTried] = useState(false);
  const save = useMutation({
    mutationFn: () => saveEmailList(token, { provider, list_id: listId.trim(), ...(apiKey.trim() ? { api_key: apiKey.trim() } : {}) }),
    onSuccess: onSaved,
  });
  const code = apiErrorCode(save.error);
  const keyError = (tried && !apiKey.trim() && !connection?.key_saved) || code === "audience_key_required" || code === "audience_unauthorized";
  const listError = (tried && !listId.trim()) || code === "invalid_audience_list" || code === "audience_list_not_found";
  const submit = () => {
    setTried(true);
    if (!listId.trim() || (!apiKey.trim() && !connection?.key_saved)) return;
    save.mutate();
  };

  return (
    <div className="space-y-3" data-testid="email-list-form">
      <Field id="email-list-provider" label={t("listProvider")}>
        <Select id="email-list-provider" aria-label={t("listProvider")} value={provider} onValueChange={(value: string) => setProvider(value as AudienceProvider)}>
          {PROVIDERS.map((item) => <option key={item} value={item}>{t(`provider.${item}`)}</option>)}
        </Select>
      </Field>
      <Field
        id="email-list-key"
        label={t("listKey")}
        hint={connection?.key_saved ? t("listKeySaved") : t(`listKeyWhere.${provider}`)}
        error={keyError ? (code === "audience_unauthorized" ? t("errors.audience_unauthorized") : t("errors.audience_key_required")) : null}
      >
        <input id="email-list-key" type="password" autoComplete="off" value={apiKey} maxLength={200} aria-invalid={keyError} onChange={(event) => setApiKey(event.target.value)} className={INPUT_CLASS} style={inputStyle(keyError)} />
      </Field>
      <Field id="email-list-id" label={t("listId")} hint={t("listIdHint")} error={listError ? (code === "audience_list_not_found" ? t("errors.audience_list_not_found") : t("errors.invalid_audience_list")) : null}>
        <input id="email-list-id" value={listId} maxLength={100} aria-invalid={listError} onChange={(event) => setListId(event.target.value)} className={INPUT_CLASS} style={inputStyle(listError)} />
      </Field>
      {save.isError && !keyError && !listError ? <ErrorNotice variant="field">{errorText(save.error)}</ErrorNotice> : null}
      <div className="flex justify-end gap-2">
        {onCancel ? <TextButton onClick={onCancel}>{t("cancel")}</TextButton> : null}
        <PrimaryButton disabled={save.isPending} onClick={submit} data-testid="email-list-connect">{t("listConnect")}</PrimaryButton>
      </div>
    </div>
  );
}
