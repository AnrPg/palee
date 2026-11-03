"use client";

import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useMemo, useState, type DragEvent } from "react";

import {
  fetchLeads,
  LEADS_KEY,
  leadsKey,
  moveLead,
  type Lead,
  type LeadStage,
} from "@/api/leads";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { Pill, primaryButtonStyle, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { ImportLeadsDialog } from "./ImportLeadsDialog";
import { LeadPanel } from "./LeadPanel";
import { NewLeadDialog } from "./NewLeadDialog";
import { canMoveTo, columns, dueState, stageCount, type OpenStage } from "./lead-model";
import { LeadAvatar, useGymTime, useLeadErrorText } from "./leads-ui";

type View = "open" | "converted" | "lost";

/**
 * «Ενδιαφερόμενοι» (ADR-344, W2 p1): a kanban of the open stages, each
 * column with its count in parentheses; cards move by dragging (desktop) or
 * from the lead's panel. «Έγινε μέλος» and «Χάθηκε» stay in their own
 * lists with their history. A card opens the side panel over the board (p2).
 */
export function LeadsBoard() {
  const t = useTranslations("Leads");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const [view, setView] = useState<View>("open");
  const [phoneStage, setPhoneStage] = useState<OpenStage>("new");
  const [selected, setSelected] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"new" | "import" | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOver] = useState<OpenStage | null>(null);
  const { zone } = useGymTime();

  const stage = view === "open" ? "open" : view;
  const list = useQuery({
    queryKey: leadsKey(stage),
    enabled: Boolean(token),
    queryFn: () => fetchLeads(token!, { stage }),
  });
  const counts = list.data?.counts;
  const now = useMemo(() => new Date(), [list.dataUpdatedAt]); // eslint-disable-line react-hooks/exhaustive-deps
  const board = useMemo(() => columns(list.data?.leads ?? [], now, zone), [list.data, now, zone]);

  const move = useMutation({
    mutationFn: ({ id, to }: { id: string; to: OpenStage }) => moveLead(token!, id, to),
    onSettled: () => queryClient.invalidateQueries({ queryKey: LEADS_KEY }),
  });

  const stageLabel = (key: LeadStage | "open") => t("withCount", { label: t(`column.${key}`), count: stageCount(counts, key) });

  function onDrop(event: DragEvent, to: OpenStage) {
    event.preventDefault();
    setOver(null);
    const id = event.dataTransfer.getData("text/plain") || dragging;
    setDragging(null);
    const lead = list.data?.leads.find((entry) => entry.id === id);
    if (lead && canMoveTo(lead, to)) move.mutate({ id: lead.id, to });
  }

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <PageHeader
          title={t("title")}
          actions={
            <>
              <button type="button" onClick={() => setDialog("import")} className={pageHeaderActionClass} style={secondaryButtonStyle}>
                {t("import")}
              </button>
              <button
                type="button"
                onClick={() => setDialog("new")}
                className={pageHeaderActionClass}
                style={primaryButtonStyle}
                data-testid="leads-new"
              >
                {t("newLead")}
              </button>
            </>
          }
        />

        <SegmentPicker<View>
          ariaLabel={t("viewLabel")}
          variant="track"
          value={view}
          onChange={setView}
          options={[
            { value: "open", label: stageLabel("open") },
            { value: "converted", label: stageLabel("converted") },
            { value: "lost", label: stageLabel("lost") },
          ]}
        />

        {list.isPending ? (
          <StatusText tone="muted">{t("loading")}</StatusText>
        ) : list.isError ? (
          <StatusText tone="error">{errorText(list.error)}</StatusText>
        ) : view === "open" ? (
          <>
            {move.isError ? <StatusText tone="error">{errorText(move.error)}</StatusText> : null}
            {/* Phones: one column at a time; dragging does not work well there. */}
            <div className="space-y-3 md:hidden">
              <SegmentPicker<OpenStage>
                ariaLabel={t("stageLabel")}
                value={phoneStage}
                onChange={setPhoneStage}
                stretch
                options={board.map((column) => ({ value: column.stage, label: stageLabel(column.stage) }))}
              />
              <CardList
                leads={board.find((column) => column.stage === phoneStage)?.leads ?? []}
                now={now}
                onOpen={setSelected}
                empty={t(`empty.${phoneStage}`)}
              />
            </div>
            <div className="hidden gap-4 md:grid md:grid-cols-3" data-testid="leads-board">
              {board.map((column) => (
                <section
                  key={column.stage}
                  aria-labelledby={`leads-col-${column.stage}`}
                  data-stage={column.stage}
                  onDragOver={(event) => {
                    event.preventDefault();
                    setOver(column.stage);
                  }}
                  onDragLeave={() => setOver((current) => (current === column.stage ? null : current))}
                  onDrop={(event) => onDrop(event, column.stage)}
                  className="flex min-h-64 flex-col gap-3 rounded-[1.6rem] p-3"
                  style={{
                    background: "var(--panel-muted)",
                    border: `1px ${over === column.stage ? "dashed var(--primary)" : "solid var(--border)"}`,
                  }}
                >
                  <h2 id={`leads-col-${column.stage}`} className="px-1 pt-1 text-sm font-bold" style={{ color: "var(--text)" }}>
                    {stageLabel(column.stage)}
                  </h2>
                  <CardList
                    leads={column.leads}
                    now={now}
                    onOpen={setSelected}
                    empty={t(`empty.${column.stage}`)}
                    draggable
                    onDragStart={setDragging}
                  />
                </section>
              ))}
            </div>
          </>
        ) : (
          <CardList leads={list.data?.leads ?? []} now={now} onOpen={setSelected} empty={t(`empty.${view}`)} archive />
        )}

        <BoxFormNote />
      </div>

      {selected ? <LeadPanel leadId={selected} onClose={() => setSelected(null)} /> : null}
      {dialog === "new" ? (
        <NewLeadDialog
          onClose={() => setDialog(null)}
          onCreated={(id) => {
            setDialog(null);
            setSelected(id);
          }}
        />
      ) : null}
      {dialog === "import" ? <ImportLeadsDialog onClose={() => setDialog(null)} /> : null}
    </main>
  );
}

function CardList({
  leads,
  now,
  onOpen,
  empty,
  draggable = false,
  archive = false,
  onDragStart,
}: {
  leads: Lead[];
  now: Date;
  onOpen: (id: string) => void;
  empty: string;
  draggable?: boolean;
  archive?: boolean;
  onDragStart?: (id: string) => void;
}) {
  if (leads.length === 0) {
    return (
      <p className="rounded-2xl px-3 py-4 text-sm" style={{ color: "var(--dim)" }}>
        {empty}
      </p>
    );
  }
  return (
    <ul className={archive ? "grid gap-2 md:grid-cols-2" : "space-y-2"}>
      {leads.map((lead) => (
        <li key={lead.id}>
          <LeadCard lead={lead} now={now} onOpen={onOpen} draggable={draggable} archive={archive} onDragStart={onDragStart} />
        </li>
      ))}
    </ul>
  );
}

function LeadCard({
  lead,
  now,
  onOpen,
  draggable,
  archive,
  onDragStart,
}: {
  lead: Lead;
  now: Date;
  onOpen: (id: string) => void;
  draggable: boolean;
  archive: boolean;
  onDragStart?: (id: string) => void;
}) {
  const t = useTranslations("Leads");
  const time = useGymTime();
  const due = dueState(lead.next_task, now, time.zone);
  const owner = lead.owner?.display_name || lead.owner?.handle;

  return (
    <button
      type="button"
      onClick={() => onOpen(lead.id)}
      draggable={draggable}
      onDragStart={(event) => {
        event.dataTransfer.setData("text/plain", lead.id);
        event.dataTransfer.effectAllowed = "move";
        onDragStart?.(lead.id);
      }}
      data-testid={`lead-card-${lead.id}`}
      className="flex w-full items-start gap-3 rounded-[1.2rem] p-3 text-start transition-transform hover:-translate-y-0.5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <LeadAvatar name={lead.name} />
      <span className="min-w-0 flex-1 space-y-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
          {lead.name}
        </span>
        <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>
          {t("cardMeta", { source: t(`source.${lead.source}`), when: time.format(lead.created_at, "day") })}
        </span>
        <span className="flex flex-wrap items-center gap-1.5">
          {archive ? (
            lead.stage === "lost" && lead.lost_reason ? (
              <Pill tone="neutral">{t(`lostReason.${lead.lost_reason}`)}</Pill>
            ) : lead.converted_at ? (
              <Pill tone="success">{t("convertedOn", { when: time.format(lead.converted_at, "day") })}</Pill>
            ) : null
          ) : (
            <>
              {owner ? (
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  {t("ownerShort", { name: owner })}
                </span>
              ) : (
                <Pill tone="warning">{t("noOwner")}</Pill>
              )}
              {lead.next_task && due !== "none" ? (
                <Pill tone={due === "late" ? "danger" : due === "today" ? "warning" : "neutral"}>
                  {t(`due.${due}`, { title: lead.next_task.title, when: time.format(lead.next_task.due_at, due === "today" ? "time" : "day-time") })}
                </Pill>
              ) : (
                <Pill tone="neutral">{t("noNextStep")}</Pill>
              )}
            </>
          )}
        </span>
      </span>
    </button>
  );
}

/** The box page form and join links bring enquiries here on their own (ADR-345). */
function BoxFormNote() {
  const t = useTranslations("Leads");
  const slug = useOrganizationSlug();
  const [copied, setCopied] = useState(false);
  if (!slug) return null;
  return (
    <p className="text-sm" style={{ color: "var(--muted)" }}>
      {t("formNote")}{" "}
      <button
        type="button"
        className="font-semibold underline-offset-2 hover:underline"
        style={{ color: "var(--primary)" }}
        onClick={() => {
          const link = `${window.location.origin}/b/${slug}`;
          void navigator.clipboard?.writeText(link).then(() => setCopied(true));
        }}
      >
        {copied ? t("linkCopied") : t("copyLink")}
      </button>
    </p>
  );
}
