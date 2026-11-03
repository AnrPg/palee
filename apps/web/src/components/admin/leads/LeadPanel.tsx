"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import { fetchAdminUsers } from "@/api/admin-users";
import {
  addLeadNote,
  addLeadTask,
  completeLeadTask,
  CONTACT_CHANNELS,
  convertLead,
  fetchLead,
  LEADS_KEY,
  leadKey,
  LOST_REASONS,
  markLeadContacted,
  moveLead,
  OPEN_STAGES,
  optOutLead,
  updateLead,
  type ContactChannel,
  type LeadDetail,
  type LeadEvent,
  type LostReason,
} from "@/api/leads";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { Pill, StatusText } from "@/components/staff/staff-ui";
import { Combobox } from "@/components/ui/Combobox";
import { DateTimeInput } from "@/components/ui/DateInput";
import { DialogButton } from "@/components/ui/Dialog";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { Select } from "@/components/ui/Select";
import { dateTimeLocalToIso } from "@/lib/zoned-time";

import { canMoveTo, eventLine, telHref, type OpenStage } from "./lead-model";
import { FieldError, FieldLabel, fieldClass, fieldStyle, LeadAvatar, useGymTime, useLeadErrorText } from "./leads-ui";

type Form = "contacted" | "note" | "task" | "convert" | "lost" | null;

/**
 * The lead's side panel over the board (W2 p2 A; full screen on phones):
 * call or email, «Επικοινώνησα», a note, the next step, the stage, «Έγινε
 * μέλος» or «Χάθηκε» with its reason, and the «Ιστορικό» with who did what
 * and when (ADR-384). One filled button per state: «Έγινε μέλος», or the
 * submit of the form that is open.
 */
export function LeadPanel({ leadId, onClose }: { leadId: string; onClose: () => void }) {
  const t = useTranslations("Leads");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const time = useGymTime();
  const [form, setForm] = useState<Form>(null);

  const detail = useQuery({
    queryKey: leadKey(leadId),
    enabled: Boolean(token),
    queryFn: () => fetchLead(token!, leadId),
  });

  const act = useMutation({
    mutationFn: (run: (token: string) => Promise<LeadDetail>) => run(token!),
    onSuccess: (data) => {
      queryClient.setQueryData(leadKey(leadId), data);
      void queryClient.invalidateQueries({ queryKey: LEADS_KEY });
      setForm(null);
    },
  });

  const lead = detail.data?.lead;
  const open = lead ? (OPEN_STAGES as readonly string[]).includes(lead.stage) : false;
  const toggle = (next: Form) => {
    act.reset();
    setForm((current) => (current === next ? null : next));
  };

  return (
    <SidePanel title={lead?.name ?? t("leadTitle")} subtitle={t("leadTitle")} onClose={onClose}>
      {detail.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : detail.isError || !lead ? (
        <StatusText tone="error">{errorText(detail.error)}</StatusText>
      ) : (
        <div className="space-y-6" data-testid="lead-panel">
          <div className="flex items-start gap-3">
            <LeadAvatar name={lead.name} />
            <div className="min-w-0 flex-1">
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                {t("cardMeta", { source: t(`source.${lead.source}`), when: time.format(lead.created_at) })}
              </p>
              <p className="mt-1 flex flex-wrap gap-1.5">
                <Pill tone={lead.stage === "converted" ? "success" : lead.stage === "lost" ? "danger" : "primary"}>
                  {t(`stage.${lead.stage}`)}
                </Pill>
                {lead.stage === "lost" && lead.lost_reason ? <Pill tone="neutral">{t(`lostReason.${lead.lost_reason}`)}</Pill> : null}
              </p>
            </div>
            <MoreMenu
              label={t("more")}
              items={[
                ...(lead.consent.marketing_at && !lead.consent.marketing_opted_out_at
                  ? [{ label: t("optOut"), onSelect: () => act.mutate((token) => optOutLead(token, lead.id)) }]
                  : []),
                ...(lead.stage === "lost"
                  ? [{ label: t("reopen"), onSelect: () => act.mutate((token) => moveLead(token, lead.id, "new")) }]
                  : []),
              ]}
            />
          </div>

          {/* Reach the person; «Επικοινώνησα» writes it in the history. */}
          <div className="flex flex-wrap gap-2">
            {telHref(lead.phone) ? <ActionLink href={telHref(lead.phone)!}>{t("call")}</ActionLink> : null}
            {lead.email ? <ActionLink href={`mailto:${lead.email}`}>{t("email")}</ActionLink> : null}
            <ActionButton active={form === "contacted"} onClick={() => toggle("contacted")}>
              {t("contacted")}
            </ActionButton>
            <ActionButton active={form === "note"} onClick={() => toggle("note")}>
              {t("note")}
            </ActionButton>
            {open ? (
              <ActionButton active={form === "task"} onClick={() => toggle("task")}>
                {t("nextStep")}
              </ActionButton>
            ) : null}
          </div>

          {form === "contacted" ? (
            <ContactedForm
              pending={act.isPending}
              onCancel={() => setForm(null)}
              onSubmit={(channel) => act.mutate((token) => markLeadContacted(token, lead.id, channel))}
            />
          ) : null}
          {form === "note" ? (
            <NoteForm
              pending={act.isPending}
              onCancel={() => setForm(null)}
              onSubmit={(text) => act.mutate((token) => addLeadNote(token, lead.id, text))}
            />
          ) : null}
          {form === "task" ? (
            <TaskForm
              pending={act.isPending}
              zone={time.zone}
              onCancel={() => setForm(null)}
              onSubmit={(title, dueAt) => act.mutate((token) => addLeadTask(token, lead.id, { title, due_at: dueAt }))}
            />
          ) : null}
          {act.isError ? <StatusText tone="error">{errorText(act.error)}</StatusText> : null}

          {open ? (
            <section className="space-y-3">
              <SegmentPicker<OpenStage>
                ariaLabel={t("stageLabel")}
                semantics="radiogroup"
                value={lead.stage as OpenStage}
                stretch
                onChange={(stage) => {
                  if (canMoveTo(lead, stage)) act.mutate((token) => moveLead(token, lead.id, stage));
                }}
                options={OPEN_STAGES.map((stage) => ({ value: stage, label: t(`stage.${stage}`) }))}
              />
              {form === "convert" ? (
                <ConvertForm
                  pending={act.isPending}
                  onCancel={() => setForm(null)}
                  onSubmit={(userId) => act.mutate((token) => convertLead(token, lead.id, userId))}
                />
              ) : form === "lost" ? (
                <LostForm
                  pending={act.isPending}
                  onCancel={() => setForm(null)}
                  onSubmit={(reason) => act.mutate((token) => moveLead(token, lead.id, "lost", reason))}
                />
              ) : (
                <div className="flex flex-wrap gap-2">
                  <DialogButton tone={form ? "secondary" : "primary"} onClick={() => toggle("convert")} testId="lead-convert">
                    {t("converted")}
                  </DialogButton>
                  <DialogButton tone="ghost" onClick={() => toggle("lost")} testId="lead-lost">
                    {t("lost")}
                  </DialogButton>
                </div>
              )}
            </section>
          ) : null}

          <section className="space-y-2">
            <Detail label={t("phone")} value={lead.phone} />
            <Detail label={t("emailLabel")} value={lead.email} />
            {lead.message ? <Detail label={t("message")} value={lead.message} /> : null}
            {lead.interests.length > 0 ? (
              <Detail label={t("interest")} value={lead.interests.map((key) => interestLabel(t, key)).join(", ")} />
            ) : null}
            <Detail
              label={t("marketing")}
              value={lead.consent.marketing_at && !lead.consent.marketing_opted_out_at ? t("yes") : t("no")}
            />
            <OwnerField
              ownerId={lead.owner?.user_id ?? null}
              ownerName={lead.owner?.display_name ?? lead.owner?.handle ?? null}
              onChange={(ownerId) => act.mutate((token) => updateLead(token, lead.id, { owner_id: ownerId }))}
            />
          </section>

          <Tasks
            detail={detail.data}
            onDone={(taskId) => act.mutate((token) => completeLeadTask(token, taskId))}
          />

          <History events={detail.data.events} />
        </div>
      )}
    </SidePanel>
  );
}

const pillButton = "min-h-10 rounded-full px-4 text-sm font-semibold";

function ActionLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} className={`${pillButton} inline-flex items-center`} style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
      {children}
    </a>
  );
}

function ActionButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={pillButton}
      style={{
        background: active ? "var(--text)" : "var(--panel-raised)",
        color: active ? "var(--bg)" : "var(--text)",
        border: `1px solid ${active ? "var(--text)" : "var(--border)"}`,
      }}
    >
      {children}
    </button>
  );
}

function FormCard({ children }: { children: ReactNode }) {
  return (
    <div className="space-y-3 rounded-[1.4rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      {children}
    </div>
  );
}

function FormActions({ pending, onCancel, submit, testId }: { pending: boolean; onCancel: () => void; submit: string; testId?: string }) {
  const t = useTranslations("Leads");
  return (
    <div className="flex flex-wrap justify-end gap-2">
      <DialogButton tone="ghost" onClick={onCancel}>
        {t("cancel")}
      </DialogButton>
      <DialogButton tone="primary" type="submit" disabled={pending} testId={testId}>
        {submit}
      </DialogButton>
    </div>
  );
}

function ContactedForm({ pending, onCancel, onSubmit }: { pending: boolean; onCancel: () => void; onSubmit: (channel: ContactChannel) => void }) {
  const t = useTranslations("Leads");
  const [channel, setChannel] = useState<ContactChannel>("phone");
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit(channel);
      }}
    >
      <FormCard>
        <SegmentPicker<ContactChannel>
          ariaLabel={t("channelLabel")}
          semantics="radiogroup"
          value={channel}
          onChange={setChannel}
          options={CONTACT_CHANNELS.map((value) => ({ value, label: t(`channel.${value}`) }))}
        />
        <FormActions pending={pending} onCancel={onCancel} submit={t("saveContacted")} testId="lead-contacted-save" />
      </FormCard>
    </form>
  );
}

function NoteForm({ pending, onCancel, onSubmit }: { pending: boolean; onCancel: () => void; onSubmit: (text: string) => void }) {
  const t = useTranslations("Leads");
  const [text, setText] = useState("");
  const [error, setError] = useState(false);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!text.trim()) return setError(true);
        onSubmit(text.trim());
      }}
    >
      <FormCard>
        <FieldLabel htmlFor="lead-note">{t("note")}</FieldLabel>
        <textarea
          id="lead-note"
          value={text}
          maxLength={2000}
          rows={3}
          onChange={(event) => {
            setText(event.target.value);
            setError(false);
          }}
          aria-invalid={error}
          aria-describedby={error ? "lead-note-error" : undefined}
          className={fieldClass}
          style={fieldStyle(error)}
        />
        <FieldError id="lead-note-error">{error ? t("field.noteRequired") : null}</FieldError>
        <FormActions pending={pending} onCancel={onCancel} submit={t("addNote")} />
      </FormCard>
    </form>
  );
}

function TaskForm({
  pending,
  zone,
  onCancel,
  onSubmit,
}: {
  pending: boolean;
  zone: string | null;
  onCancel: () => void;
  onSubmit: (title: string, dueAt: string) => void;
}) {
  const t = useTranslations("Leads");
  const [title, setTitle] = useState("");
  const [due, setDue] = useState("");
  const [errors, setErrors] = useState<{ title?: boolean; due?: boolean }>({});
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const next = { title: !title.trim(), due: !due };
        setErrors(next);
        if (next.title || next.due) return;
        onSubmit(title.trim(), dateTimeLocalToIso(due, zone));
      }}
    >
      <FormCard>
        <div>
          <FieldLabel htmlFor="lead-task-title" required>
            {t("taskTitle")}
          </FieldLabel>
          <input
            id="lead-task-title"
            value={title}
            maxLength={160}
            placeholder={t("taskPlaceholder")}
            onChange={(event) => setTitle(event.target.value)}
            aria-invalid={errors.title}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.title))}
          />
          <FieldError id="lead-task-title-error">{errors.title ? t("field.required") : null}</FieldError>
        </div>
        <div>
          <FieldLabel htmlFor="lead-task-due" required>
            {t("taskDue")}
          </FieldLabel>
          <DateTimeInput id="lead-task-due" value={due} onValueChange={setDue} className={fieldClass} style={fieldStyle(Boolean(errors.due))} />
          <FieldError id="lead-task-due-error">{errors.due ? t("field.required") : null}</FieldError>
        </div>
        <FormActions pending={pending} onCancel={onCancel} submit={t("addNextStep")} />
      </FormCard>
    </form>
  );
}

function ConvertForm({ pending, onCancel, onSubmit }: { pending: boolean; onCancel: () => void; onSubmit: (userId: string) => void }) {
  const t = useTranslations("Leads");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [text, setText] = useState("");
  const [picked, setPicked] = useState<{ id: string; label: string } | null>(null);
  const [error, setError] = useState(false);
  const search = text.trim();
  const people = useQuery({
    queryKey: ["admin", "leads", "member-search", search],
    enabled: Boolean(token) && search.length >= 2,
    queryFn: () => fetchAdminUsers(token!, { q: search, limit: 8 }),
  });
  const options = (people.data?.users ?? [])
    .filter((user) => user.client !== false)
    .map((user) => ({ id: user.id, label: user.nickname }));
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!picked) return setError(true);
        onSubmit(picked.id);
      }}
    >
      <FormCard>
        <FieldLabel htmlFor="lead-convert-person" required>
          {t("convertWho")}
        </FieldLabel>
        <Combobox
          id="lead-convert-person"
          value={text}
          onValueChange={(next) => {
            setText(next);
            setPicked(null);
            setError(false);
          }}
          options={options}
          onPick={(option) => {
            setText(option.label);
            setPicked(option);
            setError(false);
          }}
          listLabel={t("convertWho")}
          emptyText={search.length >= 2 && people.isSuccess ? t("convertNoMatch") : undefined}
          className={fieldClass}
          inputStyle={fieldStyle(error)}
          aria-invalid={error}
        />
        <FieldError id="lead-convert-error">{error ? t("field.pickMember") : null}</FieldError>
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {t("convertHint")}
        </p>
        <FormActions pending={pending} onCancel={onCancel} submit={t("convertSubmit")} testId="lead-convert-submit" />
      </FormCard>
    </form>
  );
}

function LostForm({ pending, onCancel, onSubmit }: { pending: boolean; onCancel: () => void; onSubmit: (reason: LostReason) => void }) {
  const t = useTranslations("Leads");
  const [reason, setReason] = useState<LostReason | null>(null);
  const [error, setError] = useState(false);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!reason) return setError(true);
        onSubmit(reason);
      }}
    >
      <FormCard>
        <p className="text-sm font-semibold" style={{ color: error ? "var(--danger)" : "var(--text-soft)" }}>
          {t("lostWhy")}
        </p>
        <div role="radiogroup" aria-label={t("lostWhy")} className="flex flex-wrap gap-2">
          {LOST_REASONS.map((value) => (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={reason === value}
              onClick={() => {
                setReason(value);
                setError(false);
              }}
              className="min-h-10 rounded-xl px-3 text-sm font-semibold"
              style={
                reason === value
                  ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
                  : { background: "var(--panel)", color: "var(--text-soft)", border: `1px solid ${error ? "var(--danger)" : "var(--border)"}` }
              }
            >
              {t(`lostReason.${value}`)}
            </button>
          ))}
        </div>
        <FieldError id="lead-lost-error">{error ? t("field.pickReason") : null}</FieldError>
        <FormActions pending={pending} onCancel={onCancel} submit={t("lostSubmit")} testId="lead-lost-submit" />
      </FormCard>
    </form>
  );
}

function Detail({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div className="flex items-start justify-between gap-4 text-sm">
      <span style={{ color: "var(--muted)" }}>{label}</span>
      <span className="min-w-0 break-words text-end" style={{ color: "var(--text)" }}>
        {value || "—"}
      </span>
    </div>
  );
}

function OwnerField({ ownerId, ownerName, onChange }: { ownerId: string | null; ownerName: string | null; onChange: (id: string | null) => void }) {
  const t = useTranslations("Leads");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const staff = useQuery({
    queryKey: ["admin", "leads", "staff"],
    enabled: Boolean(token),
    queryFn: () => fetchAdminUsers(token!, { limit: 200 }),
    select: (data) => data.users.filter((user) => user.staff),
  });
  const options = staff.data ?? [];
  const known = ownerId && !options.some((user) => user.id === ownerId);
  return (
    <div className="flex items-center justify-between gap-4 text-sm">
      <span style={{ color: "var(--muted)" }}>{t("owner")}</span>
      <Select
        aria-label={t("owner")}
        value={ownerId ?? ""}
        onValueChange={(value) => onChange(value || null)}
        className="min-h-10 max-w-[60%] rounded-xl px-3 text-sm"
        style={fieldStyle(false)}
      >
        <option value="">{t("noOwner")}</option>
        {known ? <option value={ownerId}>{ownerName ?? "—"}</option> : null}
        {options.map((user) => (
          <option key={user.id} value={user.id}>
            {user.nickname}
          </option>
        ))}
      </Select>
    </div>
  );
}

function Tasks({ detail, onDone }: { detail: LeadDetail; onDone: (taskId: string) => void }) {
  const t = useTranslations("Leads");
  const time = useGymTime();
  const open = detail.tasks.filter((task) => !task.done_at);
  if (open.length === 0) return null;
  return (
    <section aria-labelledby="lead-tasks" className="space-y-2">
      <h3 id="lead-tasks" className="text-sm font-bold" style={{ color: "var(--text)" }}>
        {t("nextSteps", { count: open.length })}
      </h3>
      <ul className="space-y-2">
        {open.map((task) => (
          <li key={task.id} className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                {task.title}
              </span>
              <span className="block text-xs" style={{ color: "var(--muted)" }}>
                {task.assignee?.display_name
                  ? t("taskWhenWho", { when: time.format(task.due_at), name: task.assignee.display_name })
                  : time.format(task.due_at)}
              </span>
            </span>
            <DialogButton tone="secondary" onClick={() => onDone(task.id)}>
              {t("taskDone")}
            </DialogButton>
          </li>
        ))}
      </ul>
    </section>
  );
}

function interestLabel(t: ReturnType<typeof useTranslations<"Leads">>, key: string) {
  return ["trial", "prices", "other"].includes(key) ? t(`interestOption.${key}`) : key;
}

/** «Ιστορικό»: every event with who did it and when (ADR-384), newest first. */
function History({ events }: { events: LeadEvent[] }) {
  const t = useTranslations("Leads");
  const time = useGymTime();
  const sorted = [...events].sort((a, b) => b.at.localeCompare(a.at));
  return (
    <section aria-labelledby="lead-history" className="space-y-2">
      <h3 id="lead-history" className="text-sm font-bold" style={{ color: "var(--text)" }}>
        {t("history")}
      </h3>
      <ol className="space-y-2" data-testid="lead-history">
        {sorted.map((event) => {
          const line = eventLine(event);
          const who = event.actor?.display_name || event.actor?.handle;
          return (
            <li key={event.id} className="rounded-2xl px-3 py-2.5" style={{ background: "var(--panel-muted)" }}>
              <p className="text-sm" style={{ color: "var(--text)" }}>
                {historyText(t, line)}
              </p>
              <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
                {who ? t("byWhoWhen", { name: who, when: time.format(event.at) }) : t("byPaleeWhen", { when: time.format(event.at) })}
              </p>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

function historyText(t: ReturnType<typeof useTranslations<"Leads">>, line: { key: string; values: Record<string, string> }) {
  const v = line.values;
  switch (line.key) {
    case "created":
    case "enquired_again":
      return t(`event.${line.key}`, { source: t(`source.${v.source}`) });
    case "stage_changed":
      return t("event.stage_changed", { stage: t(`stage.${v.stage}`) });
    case "lost":
      return t("event.lost", { reason: t(`lostReason.${v.reason}`) });
    case "contacted":
      return t("event.contacted", { channel: t(`channel.${v.channel}`) });
    case "note":
      return t("event.note", { text: v.text });
    case "task_added":
    case "task_done":
      return t(`event.${line.key}`, { title: v.title });
    case "message_sent":
      return t("event.message_sent", { recipe: v.recipe ? t(`recipe.${v.recipe}`) : "" });
    case "owner_changed":
    case "converted":
    case "marketing_opted_out":
    case "details_changed":
      return t(`event.${line.key}`);
    default:
      return line.key;
  }
}
