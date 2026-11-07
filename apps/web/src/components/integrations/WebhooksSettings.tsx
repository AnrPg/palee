"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { INTEGRATION_CATALOG_KEY, WEBHOOKS_KEY, createWebhook, fetchIntegrationCatalog, fetchWebhooks, type WebhookEndpoint, type WebhookEndpointWithSecret } from "@/api/integrations";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { shortUrl, webhookHealth, webhookUrlError } from "./connections-model";
import { Card, CardTitle, Field, INPUT_CLASS, Pill, PrimaryButton, SecretOnce, TextButton, inputStyle, useIntegrationError } from "./connections-ui";

export const HEALTH_TONE = { ok: "success", failing: "warning", off: "danger" } as const;

/**
 * Ρυθμίσεις › Συνδέσεις › Webhooks (W10 screen 2, option A; ADR-379): the
 * box's receivers, each with a small health badge (from option C), opening
 * the webhook's own page with its settings and delivery log. Webhooks made
 * by Zapier through a key are in the same list, marked «Από Zapier».
 */
export function WebhooksSettings({ token }: { token: string }) {
  const t = useTranslations("Connections");
  const slug = useOrganizationSlug();
  const errorText = useIntegrationError();
  const hooks = useQuery({ queryKey: WEBHOOKS_KEY, queryFn: () => fetchWebhooks(token) });
  const [creating, setCreating] = useState(false);

  return (
    <Card testId="webhooks">
      <CardTitle title={t("hooksTitle")} hint={t("hooksHint")}>
        <PrimaryButton onClick={() => setCreating(true)} data-testid="webhook-new">{t("hookNew")}</PrimaryButton>
      </CardTitle>
      {hooks.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {hooks.isError ? <ErrorNotice variant="field">{errorText(hooks.error)}</ErrorNotice> : null}
      {hooks.data?.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("hooksEmpty")}</p> : null}
      <ul className="space-y-2">
        {(hooks.data ?? []).map((hook) => (
          <li key={hook.id}>
            <Link
              href={adminHref(`/admin/settings/webhooks/${encodeURIComponent(hook.id)}`, slug)}
              className="flex items-center gap-3 rounded-2xl px-4 py-3"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              data-testid="webhook-row"
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{shortUrl(hook.url)}</span>
                <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
                  {[eventsLine(hook, t), hook.source === "api" ? t("hookFromZapier") : null].filter(Boolean).join(" · ")}
                </span>
              </span>
              <HealthPill hook={hook} />
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
            </Link>
          </li>
        ))}
      </ul>
      {creating ? <NewWebhookDialog token={token} onClose={() => setCreating(false)} /> : null}
    </Card>
  );
}

export function eventsLine(hook: Pick<WebhookEndpoint, "events">, t: (key: string) => string) {
  return hook.events.map((type) => t(`event.${type.replace(".", "_")}`)).join(" · ");
}

export function HealthPill({ hook }: { hook: WebhookEndpoint }) {
  const t = useTranslations("Connections");
  const health = webhookHealth(hook);
  return <Pill tone={HEALTH_TONE[health]}>{t(`health.${health}`)}</Pill>;
}

/** «Νέο webhook»: address and events; the signing secret is shown once. */
export function NewWebhookDialog({ token, onClose }: { token: string; onClose: () => void }) {
  const t = useTranslations("Connections");
  const queryClient = useQueryClient();
  const errorText = useIntegrationError();
  const catalog = useQuery({ queryKey: INTEGRATION_CATALOG_KEY, queryFn: () => fetchIntegrationCatalog(token) });
  const [url, setUrl] = useState("");
  const [events, setEvents] = useState<string[]>([]);
  const [tried, setTried] = useState(false);
  const [made, setMade] = useState<WebhookEndpointWithSecret | null>(null);
  const create = useMutation({
    mutationFn: () => createWebhook(token, { url: url.trim(), events }),
    onSuccess: (data) => {
      setMade(data);
      void queryClient.invalidateQueries({ queryKey: WEBHOOKS_KEY });
    },
  });
  const urlError = tried ? webhookUrlError(url) : null;
  const eventsError = tried && events.length === 0;
  const submit = () => {
    setTried(true);
    if (webhookUrlError(url) || events.length === 0) return;
    create.mutate();
  };

  return (
    <Dialog
      variant="sheet"
      size="lg"
      title={t("hookNewTitle")}
      onClose={onClose}
      dismissible={!create.isPending}
      testId="webhook-dialog"
      footer={
        made ? (
          <div className="flex justify-end"><PrimaryButton onClick={onClose}>{t("done")}</PrimaryButton></div>
        ) : (
          <div className="flex flex-wrap justify-end gap-2">
            <TextButton onClick={onClose}>{t("cancel")}</TextButton>
            <PrimaryButton disabled={create.isPending} onClick={submit} data-testid="webhook-create">{t("hookCreate")}</PrimaryButton>
          </div>
        )
      }
    >
      {made ? (
        <SecretOnce title={t("hookSecretTitle")} secret={made.secret} hint={t("hookSecretHint")} testId="webhook-secret" />
      ) : (
        <div className="space-y-4">
          <Field id="webhook-url" label={t("hookUrl")} hint={t("hookUrlHint")} error={urlError ? t(`hookUrl_${urlError}`) : null}>
            <input
              id="webhook-url"
              type="url"
              inputMode="url"
              value={url}
              maxLength={2000}
              placeholder="https://hooks.zapier.com/…"
              aria-invalid={Boolean(urlError)}
              onChange={(event) => setUrl(event.target.value)}
              className={INPUT_CLASS}
              style={inputStyle(Boolean(urlError))}
            />
          </Field>
          <EventPicker types={(catalog.data?.events ?? []).map((event) => event.type ?? "").filter(Boolean)} value={events} onChange={setEvents} invalid={eventsError} />
          {create.isError ? <ErrorNotice variant="field">{errorText(create.error)}</ErrorNotice> : null}
        </div>
      )}
    </Dialog>
  );
}

export function EventPicker({ types, value, onChange, invalid }: { types: string[]; value: string[]; onChange: (next: string[]) => void; invalid: boolean }) {
  const t = useTranslations("Connections");
  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("hookEvents")}</legend>
      {types.map((type) => (
        <label key={type} className="flex items-center gap-3 text-sm" style={{ color: "var(--text)" }}>
          <input
            type="checkbox"
            className="h-5 w-5"
            checked={value.includes(type)}
            onChange={(event) => onChange(event.target.checked ? [...value, type] : value.filter((item) => item !== type))}
          />
          <span>{t(`event.${type.replace(".", "_")}`)}</span>
        </label>
      ))}
      {invalid ? <p className="text-xs" style={{ color: "var(--danger-strong)" }}>{t("errors.invalid_events")}</p> : null}
    </fieldset>
  );
}
