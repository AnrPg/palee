"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { deletePost, FEED_KEY, type CommunityPost } from "@/api/community";
import { setAutoPost, SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { gymClubFor, initialComposeTarget } from "@/components/community/community";
import { publishToTarget, rememberedTarget, targetLabel } from "@/components/community/publish-target";
import { useMyClubs } from "@/components/community/use-community";
import { useSession } from "@/components/session-provider";
import { useSocialSummary } from "@/components/social/use-social";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import type { ShareOutcome } from "@/lib/share-card";

import { ShareCardPanel } from "./ShareCardPanel";
import { useWodCardContent } from "./subjects";

/**
 * ADR-565: the share card of a finished WOD. On the finish screen
 * (`autoPost`), a member who asked for it gets the WOD posted on Palee at
 * once, with «Αναίρεση»; one who was never asked is asked once. The post's
 * operation id is the execution's, so a reload never posts twice.
 */
export function WodShare({
  executionId,
  autoPost = false,
  onSendInApp,
  onDone,
}: {
  executionId: string;
  autoPost?: boolean;
  onSendInApp?: () => void;
  onDone: (outcome: ShareOutcome | "skipped") => void;
}) {
  const t = useTranslations("ShareCard");
  const tCommunity = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const { content } = useWodCardContent(executionId);
  const clubs = useMyClubs();
  const clubList = useMemo(() => clubs.data ?? [], [clubs.data]);
  const summary = useSocialSummary();
  const enabled = autoPost && summary.isSuccess ? (summary.data.auto_post?.enabled ?? null) : undefined;
  const [post, setPost] = useState<CommunityPost | null>(null);
  const [undone, setUndone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const started = useRef(false);
  const club = gymClubFor(clubList, null);
  const target = initialComposeTarget(clubList, rememberedTarget(), club?.id ?? null);
  const label = targetLabel(clubList, target, tCommunity);

  async function postNow() {
    if (!token || started.current) return;
    started.current = true;
    try {
      const created = await publishToTarget(token, clubList, target, {
        attachment_type: "workout_execution",
        attachment_id: executionId,
        client_operation_id: `wod-auto-${executionId}`,
      });
      setPost(created);
      await queryClient.invalidateQueries({ queryKey: FEED_KEY });
    } catch (caught) {
      started.current = false;
      setError(`${t("paleeFailed")} ${clientErrorMessage(caught, tUi)}`);
    }
  }

  useEffect(() => {
    if (enabled === true && clubs.isFetched && !started.current) void postNow();
    // postNow reads the latest clubs and target; it runs once per finished WOD.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, clubs.isFetched]);

  async function answer(yes: boolean) {
    if (!token) return;
    try {
      const setting = await setAutoPost(token, yes);
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) => (current ? { ...current, auto_post: setting } : current));
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    }
  }

  async function undo() {
    if (!token || !post) return;
    try {
      await deletePost(token, post);
      setPost(null);
      setUndone(true);
      await queryClient.invalidateQueries({ queryKey: FEED_KEY });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    }
  }

  if (!content) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("preparing")}</p>;

  return (
    <div className="flex w-full flex-col gap-3">
      {enabled === null && !post ? (
        <section
          aria-labelledby="auto-post-ask"
          className="flex flex-col gap-2 rounded-2xl p-3"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
        >
          <p id="auto-post-ask" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("autoAsk")}
          </p>
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("autoAskHint", { target: label })}</p>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => void answer(true)}
              className="min-h-10 flex-1 rounded-xl text-sm font-bold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("autoYes")}
            </button>
            <button
              type="button"
              onClick={() => void answer(false)}
              className="min-h-10 flex-1 rounded-xl text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("autoNo")}
            </button>
          </div>
        </section>
      ) : null}
      {post ? (
        <div role="status" className="flex items-center justify-between gap-3 rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}>
          <span>{t("autoPosted", { target: label })}</span>
          <button type="button" onClick={() => void undo()} className="min-h-10 font-bold" style={{ color: "var(--spark)" }}>
            {t("undo")}
          </button>
        </div>
      ) : null}
      {undone ? (
        <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("undone")}
        </p>
      ) : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      <ShareCardPanel
        content={content}
        attachment={{ type: "workout_execution", id: executionId }}
        posted={post ? { label } : null}
        onSendInApp={onSendInApp}
        onDone={onDone}
      />
    </div>
  );
}
