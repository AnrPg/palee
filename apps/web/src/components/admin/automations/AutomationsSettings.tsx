"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import {
  AUTOMATION_MESSAGES_KEY,
  automationsKey,
  fetchAutomationMessages,
  fetchAutomations,
  previewAutomation,
  updateAutomation,
  type Recipe,
  type RecipeList,
} from "@/api/leads";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { FieldError, FieldLabel, fieldClass, fieldStyle, useGymTime, useLeadErrorText } from "@/components/admin/leads/leads-ui";
import { useSession } from "@/components/session-provider";
import { Pill, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";

import {
  changes,
  draftOf,
  hasDelay,
  RECIPE_SETTING,
  sentCount,
  settingValue,
  toggleChannel,
  validateDraft,
  type DraftErrors,
  type RecipeDraft,
} from "./automations-model";

/**
 * «Αυτοματισμοί» (ADR-346, W2 p3 A): the six ready recipes, each off until
 * the box switches it on, with a switch on its row. A row opens its editor
 * on the side: channels in order, subject and text with placeholders, a
 * preview; the timing sits under «Προχωρημένα». Never a workflow builder.
 */
export function AutomationsSettings() {
  const t = useTranslations("Automations");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const [editing, setEditing] = useState<Recipe["key"] | null>(null);
  const [showSent, setShowSent] = useState(false);

  const list = useQuery({
    queryKey: automationsKey(locale),
    enabled: Boolean(token),
    queryFn: () => fetchAutomations(token!, locale),
  });

  const toggle = useMutation({
    mutationFn: ({ key, enabled }: { key: Recipe["key"]; enabled: boolean }) => updateAutomation(token!, key, locale, { enabled }),
    onSuccess: (recipe) => replaceRecipe(queryClient, locale, recipe),
  });

  const recipe = list.data?.recipes.find((entry) => entry.key === editing) ?? null;

  return (
    <div>
      <div className="space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("title")}</h2>
          <button type="button" onClick={() => setShowSent(true)} className="rounded-full px-4 py-2 text-sm font-semibold" style={secondaryButtonStyle}>
            {t("sent")}
          </button>
        </div>
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {t("intro")}
        </p>

        {list.isPending ? (
          <StatusText tone="muted">{t("loading")}</StatusText>
        ) : list.isError ? (
          <StatusText tone="error">{errorText(list.error)}</StatusText>
        ) : (
          <ul
            className="divide-y overflow-hidden rounded-[1.6rem]"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", borderColor: "var(--border)" }}
            data-testid="automations-list"
          >
            {list.data.recipes.map((entry) => (
              <li key={entry.key} className="flex items-center gap-3 px-4 py-3.5" style={{ borderColor: "var(--border)" }}>
                <button type="button" onClick={() => setEditing(entry.key)} className="min-w-0 flex-1 text-start" data-testid={`recipe-${entry.key}`}>
                  <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {t(`recipe.${entry.key}`)}
                  </span>
                  <span className="block text-xs" style={{ color: "var(--muted)" }}>
                    {t(`when.${entry.key}`, { days: settingValue(entry) ?? 0 })}
                    {" · "}
                    {entry.channels.map((channel) => channelLabel(t, channel)).join(" → ")}
                  </span>
                </button>
                {entry.enabled && sentCount(entry) > 0 ? (
                  <span className="hidden sm:inline-flex">
                    <Pill tone="success">{t("sentCount", { count: sentCount(entry), days: list.data.stats_days })}</Pill>
                  </span>
                ) : null}
                <Toggle
                  checked={entry.enabled}
                  label={t("switchLabel", { name: t(`recipe.${entry.key}`) })}
                  disabled={toggle.isPending}
                  onChange={(enabled) => toggle.mutate({ key: entry.key, enabled })}
                />
              </li>
            ))}
          </ul>
        )}
        {toggle.isError ? <StatusText tone="error">{errorText(toggle.error)}</StatusText> : null}
      </div>

      {recipe && list.data ? (
        <RecipeEditor key={recipe.key} recipe={recipe} list={list.data} onClose={() => setEditing(null)} />
      ) : null}
      {showSent ? <SentDialog onClose={() => setShowSent(false)} /> : null}
    </div>
  );
}

function replaceRecipe(queryClient: ReturnType<typeof useQueryClient>, locale: string, recipe: Recipe) {
  queryClient.setQueryData<RecipeList>(automationsKey(locale), (data) =>
    data ? { ...data, recipes: data.recipes.map((entry) => (entry.key === recipe.key ? recipe : entry)) } : data,
  );
}

function channelLabel(t: ReturnType<typeof useTranslations<"Automations">>, channel: string) {
  return ["in_app", "email", "sms"].includes(channel) ? t(`channel.${channel}`) : channel;
}

function RecipeEditor({ recipe, list, onClose }: { recipe: Recipe; list: RecipeList; onClose: () => void }) {
  const t = useTranslations("Automations");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const [draft, setDraft] = useState<RecipeDraft>(() => draftOf(recipe));
  const [errors, setErrors] = useState<DraftErrors>({});
  const [advanced, setAdvanced] = useState(false);
  const [previewText, setPreviewText] = useState({ subject: draft.subject, body: draft.body });
  const setting = RECIPE_SETTING[recipe.key];

  // The preview follows the text a moment after typing stops.
  useEffect(() => {
    const timer = window.setTimeout(() => setPreviewText({ subject: draft.subject, body: draft.body }), 400);
    return () => window.clearTimeout(timer);
  }, [draft.subject, draft.body]);

  const preview = useQuery({
    queryKey: ["admin", "automations", "preview", recipe.key, locale, previewText.subject, previewText.body],
    enabled: Boolean(token) && Boolean(previewText.body.trim()),
    queryFn: () => previewAutomation(token!, recipe.key, { locale, subject: previewText.subject, body: previewText.body }),
    placeholderData: (previous) => previous,
  });

  const save = useMutation({
    mutationFn: () => updateAutomation(token!, recipe.key, locale, changes(recipe, draft)),
    onSuccess: (saved) => {
      replaceRecipe(queryClient, locale, saved);
      onClose();
    },
  });

  const set = <K extends keyof RecipeDraft>(key: K, value: RecipeDraft[K]) => {
    setDraft((current) => ({ ...current, [key]: value }));
    setErrors((current) => ({ ...current, [key]: undefined }));
  };

  function submit() {
    const next = validateDraft(recipe, draft);
    setErrors(next);
    if (Object.keys(next).length === 0) save.mutate();
  }

  return (
    <SidePanel
      title={t(`recipe.${recipe.key}`)}
      subtitle={t("title")}
      onClose={onClose}
      footer={
        <div className="flex flex-wrap items-center justify-between gap-2">
          <DialogButton
            tone="ghost"
            onClick={() => setDraft((current) => ({ ...current, subject: recipe.default_subject, body: recipe.default_body }))}
          >
            {t("resetText")}
          </DialogButton>
          <div className="flex gap-2">
            <DialogButton tone="ghost" onClick={onClose}>
              {t("cancel")}
            </DialogButton>
            <DialogButton tone="primary" onClick={submit} disabled={save.isPending} testId="recipe-save">
              {t("save")}
            </DialogButton>
          </div>
        </div>
      }
    >
      <div className="space-y-5" data-testid="recipe-editor">
        <div className="flex items-center justify-between gap-3">
          <span>
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("enabled")}
            </span>
            <span className="block text-xs" style={{ color: "var(--muted)" }}>
              {t(`when.${recipe.key}`, { days: Number(draft.setting) || 0 })}
            </span>
          </span>
          <Toggle checked={draft.enabled} label={t("enabled")} onChange={(value) => set("enabled", value)} />
        </div>

        {setting ? (
          <div>
            <FieldLabel htmlFor="recipe-setting">{t(`setting.${recipe.key}`)}</FieldLabel>
            <input
              id="recipe-setting"
              inputMode="numeric"
              value={draft.setting}
              onChange={(event) => set("setting", event.target.value.replace(/[^\d]/g, ""))}
              aria-invalid={Boolean(errors.setting)}
              className={`${fieldClass} max-w-[8rem]`}
              style={fieldStyle(Boolean(errors.setting))}
            />
            <FieldError id="recipe-setting-error">{errors.setting ? t("field.between", { min: setting.min, max: setting.max }) : null}</FieldError>
          </div>
        ) : null}

        <div>
          <p className="mb-1 text-sm font-semibold" style={{ color: errors.channels ? "var(--danger)" : "var(--text-soft)" }}>
            {t("how")}
          </p>
          <div className="flex flex-wrap gap-2" role="group" aria-label={t("how")}>
            {list.channels.map((channel) => {
              const position = draft.channels.indexOf(channel);
              const on = position >= 0;
              return (
                <button
                  key={channel}
                  type="button"
                  aria-pressed={on}
                  onClick={() => set("channels", toggleChannel(draft.channels, channel))}
                  className="inline-flex min-h-10 items-center gap-2 rounded-xl px-3 text-sm font-semibold"
                  style={
                    on
                      ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
                      : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }
                  }
                >
                  {on ? <span className="text-xs tabular-nums">{position + 1}</span> : null}
                  {channelLabel(t, channel)}
                </button>
              );
            })}
          </div>
          <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
            {t("channelsHint")}
          </p>
          <FieldError id="recipe-channels-error">{errors.channels ? t("field.channels") : null}</FieldError>
        </div>

        <div>
          <FieldLabel htmlFor="recipe-subject" required>
            {t("subject")}
          </FieldLabel>
          <input
            id="recipe-subject"
            value={draft.subject}
            maxLength={200}
            onChange={(event) => set("subject", event.target.value)}
            aria-invalid={Boolean(errors.subject)}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.subject))}
          />
          <FieldError id="recipe-subject-error">{errors.subject ? t("field.required") : null}</FieldError>
        </div>
        <div>
          <FieldLabel htmlFor="recipe-body" required>
            {t("body")}
          </FieldLabel>
          <textarea
            id="recipe-body"
            value={draft.body}
            rows={5}
            maxLength={2000}
            onChange={(event) => set("body", event.target.value)}
            aria-invalid={Boolean(errors.body)}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.body))}
          />
          <FieldError id="recipe-body-error">{errors.body ? t("field.required") : null}</FieldError>
          <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
            {t("placeholders", { list: list.placeholders.map((name) => `{${name}}`).join(", ") })}
          </p>
        </div>

        {preview.data ? (
          <div className="rounded-2xl p-3" style={{ background: "var(--panel-muted)" }} data-testid="recipe-preview">
            <p className="text-[11px] font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {t("preview")}
            </p>
            <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
              {preview.data.subject}
            </p>
            <p className="mt-1 whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>
              {preview.data.body}
            </p>
          </div>
        ) : null}

        <button
          type="button"
          aria-expanded={advanced}
          onClick={() => setAdvanced((value) => !value)}
          className="text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {t("advanced")}
        </button>
        {advanced ? (
          <div className="space-y-3">
            {hasDelay(recipe) ? (
              <div>
                <FieldLabel htmlFor="recipe-delay">{t("delay")}</FieldLabel>
                <input
                  id="recipe-delay"
                  inputMode="numeric"
                  value={draft.delay}
                  onChange={(event) => set("delay", event.target.value.replace(/[^\d]/g, ""))}
                  aria-invalid={Boolean(errors.delay)}
                  className={`${fieldClass} max-w-[8rem]`}
                  style={fieldStyle(Boolean(errors.delay))}
                />
                <FieldError id="recipe-delay-error">{errors.delay ? t("field.between", { min: 0, max: 43200 }) : null}</FieldError>
              </div>
            ) : null}
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {t("quietHours")}
            </p>
          </div>
        ) : null}
        {save.isError ? <StatusText tone="error">{errorText(save.error)}</StatusText> : null}
      </div>
    </SidePanel>
  );
}

/** «Απεσταλμένα»: the latest automatic messages, with whom and when. */
function SentDialog({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Automations");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const errorText = useLeadErrorText();
  const time = useGymTime();
  const messages = useQuery({
    queryKey: AUTOMATION_MESSAGES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchAutomationMessages(token!),
  });
  return (
    <Dialog onClose={onClose} title={t("sent")} size="lg" testId="automation-messages">
      {messages.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : messages.isError ? (
        <StatusText tone="error">{errorText(messages.error)}</StatusText>
      ) : messages.data.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {t("sentEmpty")}
        </p>
      ) : (
        <ul className="space-y-2">
          {messages.data.map((message) => (
            <li key={message.id} className="flex items-start justify-between gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
              <span className="min-w-0">
                <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {message.recipient.name ?? "—"}
                </span>
                <span className="block text-xs" style={{ color: "var(--muted)" }}>
                  {t("sentLine", {
                    recipe: t(`recipe.${message.recipe}`),
                    when: time.format(message.sent_at ?? message.due_at),
                  })}
                </span>
              </span>
              <Pill tone={message.status === "sent" ? "success" : message.status === "failed" ? "danger" : "neutral"}>
                {t(`status.${message.status}`)}
              </Pill>
            </li>
          ))}
        </ul>
      )}
    </Dialog>
  );
}
