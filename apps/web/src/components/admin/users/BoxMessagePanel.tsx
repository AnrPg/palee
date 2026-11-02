"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import {
  fetchThreadMessages,
  fetchThreads,
  getOrCreateContextThread,
  MESSAGE_TOPICS,
  sendMessage,
  type MessageTopic,
} from "@/api/messaging";
import { MessageBubble } from "@/components/chat/MessageBubble";
import { TOPIC_KEYS } from "@/components/chat/message-topics";
import { inboxHref } from "@/components/chat/inbox/inbox-model";
import { useSession } from "@/components/session-provider";
import {
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/** How many of the latest messages the panel shows; the rest are in Μηνύματα. */
const HISTORY_LIMIT = 20;

/**
 * «Μήνυμα από το box» (ADR-140 §6): operational staff write to the member in
 * the gym's thread with them, which any permitted staff member can continue.
 * The panel shows that conversation above the box (both sides, the box's
 * messages on the right whoever on the staff wrote them), so what was sent is
 * always in view, with a way into Μηνύματα for the whole thread. Looking
 * never creates a thread; the first send does.
 */
export function BoxMessagePanel({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [body, setBody] = useState("");
  const [topic, setTopic] = useState<MessageTopic | null>(null);
  const queryClient = useQueryClient();
  const threadKey = ["messaging", "box-thread", userId] as const;

  // The box's thread with this person, if one exists yet.
  const threadQuery = useQuery({
    queryKey: threadKey,
    enabled: Boolean(token),
    queryFn: async () => {
      const { threads } = await fetchThreads(token!, "box");
      return (threads ?? []).find((thread) => thread.context_type === "box" && thread.context_id === userId) ?? null;
    },
  });
  const threadId = threadQuery.data?.id ?? null;
  const historyQuery = useQuery({
    queryKey: ["messaging", "thread-messages", threadId, HISTORY_LIMIT],
    enabled: Boolean(token && threadId),
    queryFn: () => fetchThreadMessages(token!, threadId!, { limit: HISTORY_LIMIT }),
  });
  const history = historyQuery.data?.messages ?? [];

  const send = useMutation({
    mutationFn: async () => {
      const { thread } = await getOrCreateContextThread(token!, "box", userId);
      await sendMessage(token!, thread.id, body.trim(), { messageType: "box_message", topic });
      return thread.id;
    },
    onSuccess: async () => {
      setBody("");
      setTopic(null);
      await queryClient.invalidateQueries({ queryKey: threadKey });
      await queryClient.invalidateQueries({ queryKey: ["messaging", "thread-messages"] });
    },
  });
  const openThreadId = threadId ?? send.data ?? null;

  return (
    <form
      className="space-y-3"
      onSubmit={(event) => {
        event.preventDefault();
        send.mutate();
      }}
    >
      {history.length > 0 ? (
        <section aria-label={i18n("bmHistory")} data-testid="box-message-history" className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("bmHistory")}</p>
          <div className="scroll-area flex max-h-80 flex-col gap-2 overflow-y-auto rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            {history.map((message) => (
              <MessageBubble key={message.id} message={message} isOwnMessage={message.sender_id !== userId} />
            ))}
          </div>
        </section>
      ) : null}
      {historyQuery.isError ? <StatusText tone="error">{i18n("bmHistoryError")}</StatusText> : null}
      <div role="radiogroup" aria-label={i18n("msgTopic")} className="flex flex-wrap gap-1.5">
        {MESSAGE_TOPICS.map((item) => (
          <button
            key={item}
            type="button"
            role="radio"
            aria-checked={topic === item}
            onClick={() => setTopic((current) => (current === item ? null : item))}
            className="rounded-full px-3 py-1 text-xs font-semibold"
            style={
              topic === item
                ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                : { background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }
            }
          >
            {i18n(TOPIC_KEYS[item])}
          </button>
        ))}
      </div>
      <textarea
        aria-label={i18n("bmBody")}
        placeholder={i18n("bmPlaceholder")}
        className={`${inputClass} min-h-24`}
        style={inputStyle}
        maxLength={5000}
        value={body}
        onChange={(event) => {
          setBody(event.target.value);
          if (send.isSuccess || send.isError) send.reset();
        }}
      />
      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" disabled={!token || send.isPending || !body.trim()} className={primaryButtonClass} style={primaryButtonStyle}>
          {send.isPending ? i18n("sendingcf76551") : i18n("send9bc2575")}
        </button>
        {openThreadId ? (
          <Link
            href={inboxHref({ filter: "clubs", thread: openThreadId })}
            className="text-sm font-semibold"
            style={{ color: "var(--primary-strong)" }}
            data-testid="box-message-open"
          >
            {send.isSuccess ? i18n("bmSentOpen") : i18n("bmOpenInMessages")}
          </Link>
        ) : null}
      </div>
      {send.isError ? <StatusText tone="error">{localizeError(send.error, i18n)}</StatusText> : null}
    </form>
  );
}
