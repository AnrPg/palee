"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  INTEGRATION_CATALOG_KEY,
  WEBHOOKS_KEY,
  deleteWebhook,
  deliveriesKey,
  deliveryKey,
  fetchDeliveries,
  fetchDelivery,
  fetchIntegrationCatalog,
  fetchWebhooks,
  replayDelivery,
  rotateWebhookSecret,
  testWebhook,
  updateWebhook,
  type WebhookDelivery,
  type WebhookEndpoint,
} from "@/api/integrations";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { DELIVERY_FILTERS, deliveryState, deliveryStatusParam, shortUrl, type DeliveryFilter } from "./connections-model";
import { Card, CardTitle, OutlineButton, Pill, PrimaryButton, SecretOnce, TextButton, useIntegrationError, useWhen } from "./connections-ui";
import { EventPicker, HealthPill, eventsLine } from "./WebhooksSettings";

const STATE_TONE = { delivered: "success", retrying: "warning", failed: "danger" } as const;

/**
 * One webhook's own page (W10 screen 2, option A; ADR-379): its address,
 * events and switch on top with «Δοκιμή» and «Νέο μυστικό υπογραφής», then
 * the delivery log; a delivery opens with its payload and every attempt,
 * and «Ξανά» sits right there.
 */
export function WebhookPage({ endpointId }: { endpointId: string }) {
  const t = useTranslations("Connections");
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const hooks = useQuery({ queryKey: WEBHOOKS_KEY, queryFn: () => fetchWebhooks(token!), enabled: Boolean(token) });
  const hook = hooks.data?.find((item) => item.id === endpointId) ?? null;
  const back = adminHref("/admin/settings?connections=webhooks#connections", slug);

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }} data-testid="webhook-page">
      <div className="mx-auto max-w-3xl space-y-4">
        <BackLink href={back}>{t("connectionsBack")}</BackLink>
        {hooks.isLoading || !token ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {hooks.isSuccess && !hook ? <ErrorNotice>{t("hookMissing")}</ErrorNotice> : null}
        {hook && token ? (
          <>
            <EndpointHead token={token} hook={hook} back={back} />
            <DeliveryLog token={token} hook={hook} />
          </>
        ) : null}
      </div>
    </main>
  );
}

function EndpointHead({ token, hook, back }: { token: string; hook: WebhookEndpoint; back: string }) {
  const t = useTranslations("Connections");
  const router = useRouter();
  const queryClient = useQueryClient();
  const errorText = useIntegrationError();
  const [secret, setSecret] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const refresh = () => void queryClient.invalidateQueries({ queryKey: WEBHOOKS_KEY });
  const invalidateLog = () => void queryClient.invalidateQueries({ queryKey: ["admin", "integrations", "deliveries", hook.id] });

  const test = useMutation({ mutationFn: () => testWebhook(token, hook.id), onSuccess: invalidateLog });
  const rotate = useMutation({ mutationFn: () => rotateWebhookSecret(token, hook.id), onSuccess: (data) => { setSecret(data.secret); refresh(); } });
  const toggle = useMutation({ mutationFn: (status: "active" | "disabled") => updateWebhook(token, hook.id, { status }), onSuccess: refresh });
  const remove = useMutation({ mutationFn: () => deleteWebhook(token, hook.id), onSuccess: () => { refresh(); router.push(back); } });
  const failure = test.error ?? rotate.error ?? toggle.error ?? remove.error;

  return (
    <Card testId="webhook-head">
      <CardTitle title={shortUrl(hook.url)} hint={eventsLine(hook, t)}>
        <HealthPill hook={hook} />
        <MoreMenu
          label={t("more")}
          items={[
            { label: t("hookEdit"), onSelect: () => setEditing(true) },
            hook.status === "active"
              ? { label: t("hookTurnOff"), onSelect: () => toggle.mutate("disabled") }
              : { label: t("hookTurnOn"), onSelect: () => toggle.mutate("active") },
          ]}
        />
      </CardTitle>
      {hook.status !== "active" && hook.disabled_reason ? (
        <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)", color: "var(--text)" }} data-testid="webhook-closed">
          {t("hookClosed")}
        </p>
      ) : null}
      {hook.source === "api" ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("hookFromZapier")}</p> : null}
      <div className="flex flex-wrap gap-2">
        <OutlineButton disabled={test.isPending || hook.status !== "active"} onClick={() => test.mutate()} data-testid="webhook-test">{t("hookTest")}</OutlineButton>
        <ConfirmButton label={t("hookNewSecret")} question={t("hookNewSecretQuestion")} confirmLabel={t("hookNewSecret")} pending={rotate.isPending} onConfirm={() => rotate.mutate()} />
        <ConfirmButton label={t("hookDelete")} question={t("hookDeleteQuestion")} confirmLabel={t("hookDelete")} pending={remove.isPending} onConfirm={() => remove.mutate()} />
      </div>
      {test.isSuccess ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("hookTestSent")}</p> : null}
      {secret ? <SecretOnce title={t("hookSecretTitle")} secret={secret} hint={t("hookSecretRotatedHint")} /> : null}
      {failure ? <ErrorNotice variant="field">{errorText(failure)}</ErrorNotice> : null}
      {editing ? <EditWebhookDialog token={token} hook={hook} onClose={() => setEditing(false)} /> : null}
    </Card>
  );
}

function EditWebhookDialog({ token, hook, onClose }: { token: string; hook: WebhookEndpoint; onClose: () => void }) {
  const t = useTranslations("Connections");
  const queryClient = useQueryClient();
  const errorText = useIntegrationError();
  const catalog = useQuery({ queryKey: INTEGRATION_CATALOG_KEY, queryFn: () => fetchIntegrationCatalog(token) });
  const [events, setEvents] = useState<string[]>(hook.events);
  const save = useMutation({
    mutationFn: () => updateWebhook(token, hook.id, { events }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: WEBHOOKS_KEY });
      onClose();
    },
  });
  return (
    <Dialog
      variant="sheet"
      size="md"
      title={t("hookEdit")}
      onClose={onClose}
      dismissible={!save.isPending}
      footer={
        <div className="flex justify-end gap-2">
          <TextButton onClick={onClose}>{t("cancel")}</TextButton>
          <PrimaryButton disabled={save.isPending || events.length === 0} onClick={() => save.mutate()}>{t("save")}</PrimaryButton>
        </div>
      }
    >
      <EventPicker types={(catalog.data?.events ?? []).map((event) => event.type ?? "").filter(Boolean)} value={events} onChange={setEvents} invalid={events.length === 0} />
      {save.isError ? <ErrorNotice variant="field">{errorText(save.error)}</ErrorNotice> : null}
    </Dialog>
  );
}

function DeliveryLog({ token, hook }: { token: string; hook: WebhookEndpoint }) {
  const t = useTranslations("Connections");
  const locale = useUiLocale();
  const when = useWhen();
  const errorText = useIntegrationError();
  const [filter, setFilter] = useState<DeliveryFilter>("all");
  const [selected, setSelected] = useState<string | null>(null);
  const log = useQuery({ queryKey: deliveriesKey(hook.id, filter), queryFn: () => fetchDeliveries(token, hook.id, deliveryStatusParam(filter)) });

  return (
    <Card testId="delivery-log">
      <CardTitle title={t("deliveriesTitle")} hint={t("deliveriesHint")} />
      <SegmentPicker
        ariaLabel={t("deliveriesTitle")}
        options={DELIVERY_FILTERS.map((value) => ({ value, label: t(`deliveryFilter.${value}`) }))}
        value={filter}
        onChange={setFilter}
      />
      {log.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {log.isError ? <ErrorNotice variant="field">{errorText(log.error)}</ErrorNotice> : null}
      {log.data?.deliveries.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("deliveriesEmpty")}</p> : null}
      <ul className="space-y-2">
        {(log.data?.deliveries ?? []).map((delivery) => {
          const state = deliveryState(delivery);
          return (
            <li key={delivery.id}>
              <button
                type="button"
                onClick={() => setSelected(delivery.id)}
                className="flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-start"
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                data-testid="delivery-row"
              >
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {t(`event.${delivery.event_type.replace(".", "_")}`)} <span className="font-mono text-xs" style={{ color: "var(--dim)" }}>{delivery.event_type}</span>
                  </span>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>
                    {[when(delivery.created_at, locale), delivery.last_status_code ? `HTTP ${delivery.last_status_code}` : null, t("attempts", { count: delivery.attempts })].filter(Boolean).join(" · ")}
                  </span>
                </span>
                <Pill tone={STATE_TONE[state]}>{state === "retrying" && delivery.next_attempt_at ? t("deliveryRetryAt", { when: when(delivery.next_attempt_at, locale) }) : t(`deliveryState.${state}`)}</Pill>
              </button>
            </li>
          );
        })}
      </ul>
      {selected ? <DeliveryDialog token={token} deliveryId={selected} onClose={() => setSelected(null)} /> : null}
    </Card>
  );
}

function DeliveryDialog({ token, deliveryId, onClose }: { token: string; deliveryId: string; onClose: () => void }) {
  const t = useTranslations("Connections");
  const locale = useUiLocale();
  const when = useWhen();
  const errorText = useIntegrationError();
  const queryClient = useQueryClient();
  const detail = useQuery({ queryKey: deliveryKey(deliveryId), queryFn: () => fetchDelivery(token, deliveryId) });
  const replay = useMutation({
    mutationFn: () => replayDelivery(token, deliveryId),
    onSuccess: (delivery: WebhookDelivery) => void queryClient.invalidateQueries({ queryKey: ["admin", "integrations", "deliveries", delivery.endpoint_id] }),
  });
  const delivery = detail.data;
  const state = delivery ? deliveryState(delivery) : null;

  return (
    <Dialog
      variant="panel"
      size="lg"
      title={delivery ? t(`event.${delivery.event_type.replace(".", "_")}`) : t("loading")}
      onClose={onClose}
      testId="delivery-detail"
      footer={
        <div className="flex flex-wrap items-center justify-end gap-2">
          <span className="mr-auto text-xs" style={{ color: "var(--dim)" }}>{t("retrySchedule")}</span>
          <PrimaryButton disabled={!delivery || state === "retrying" || replay.isPending} onClick={() => replay.mutate()} data-testid="delivery-replay">{t("replay")}</PrimaryButton>
        </div>
      }
    >
      {detail.isError ? <ErrorNotice variant="field">{errorText(detail.error)}</ErrorNotice> : null}
      {delivery && state ? (
        <div className="space-y-3">
          <Pill tone={STATE_TONE[state]}>{t(`deliveryState.${state}`)}</Pill>
          <pre className="overflow-x-auto rounded-2xl p-3 font-mono text-xs" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}>
            {JSON.stringify(delivery.payload ?? {}, null, 2)}
          </pre>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("payloadHint")}</p>
          <ul className="divide-y rounded-2xl" style={{ border: "1px solid var(--border)", borderColor: "var(--border)" }}>
            {(delivery.attempts_log ?? []).map((attempt) => (
              <li key={attempt.attempt} className="px-4 py-2" style={{ borderColor: "var(--border)" }}>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("attemptLine", { n: attempt.attempt, when: when(attempt.started_at, locale) })}</p>
                <p className="text-xs" style={{ color: "var(--dim)" }}>
                  {[attempt.status_code ? `HTTP ${attempt.status_code}` : null, attempt.duration_ms != null ? `${attempt.duration_ms} ms` : null, attempt.error ?? attempt.response_excerpt ?? null].filter(Boolean).join(" · ")}
                </p>
              </li>
            ))}
          </ul>
          {replay.isSuccess ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("replayQueued")}</p> : null}
          {replay.isError ? <ErrorNotice variant="field">{errorText(replay.error)}</ErrorNotice> : null}
        </div>
      ) : null}
    </Dialog>
  );
}
