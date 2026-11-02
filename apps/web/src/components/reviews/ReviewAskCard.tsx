"use client";

import Link from "next/link";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { fetchReviewAsk, respondToReviewAsk, type ReviewAskAction } from "@/api/box-site";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { boxChatHref } from "@/components/trials/box-chat-links";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { ReviewSheet } from "./ReviewSheet";

/**
 * ANR s6 A, ADR-386: after the 10th, 50th or 100th class, a card on Αρχική
 * the first time the app opens, then never again (no push, no reminders).
 * Three answers for everyone, whatever they think of the box (no gating):
 * «Γράψε κριτική», «Γράψε και στο Google», «Πες κάτι στο box».
 */
export function ReviewAskCard() {
  const t = useTranslations("BoxReviews");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const organizationId = membership?.organization.id ?? null;
  // The server records the ask when it hands it out and never returns it again: read it once per session.
  const ask = useQuery({
    queryKey: ["me", "review-ask", organizationId],
    enabled: Boolean(token && organizationId),
    queryFn: () => fetchReviewAsk(token),
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
    retry: false,
  });
  const [closed, setClosed] = useState(false);
  const [writing, setWriting] = useState(false);
  const respond = useMutation({ mutationFn: (action: ReviewAskAction) => respondToReviewAsk(token, ask.data!.id, action) });
  const data = ask.data;
  if (!data || !membership || closed) return writing && data && membership ? <ReviewSheet token={token} boxName={membership.organization.name} mine={null} onClose={() => setWriting(false)} /> : null;

  const box = membership.organization.name;
  const answer = (action: ReviewAskAction) => respond.mutate(action);
  const buttonClass = "flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold";
  const outlined = { border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <HubCard eyebrow={box} highlighted>
      <div className="flex flex-col gap-3" data-testid="review-ask-card">
        <div className="flex items-start justify-between gap-3">
          <p className="text-base font-bold" style={{ color: "var(--text)" }}>{t("ask.title", { count: data.milestone })}</p>
          <button
            type="button"
            onClick={() => {
              answer("dismissed");
              setClosed(true);
            }}
            aria-label={t("ask.close")}
            className="grid h-9 w-9 shrink-0 place-items-center rounded-full"
            style={{ color: "var(--dim)" }}
            data-testid="review-ask-close"
          >
            ✕
          </button>
        </div>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ask.text", { box })}</p>
        <div className="flex flex-col gap-2 sm:flex-row">
          {!data.has_review ? (
            <button
              type="button"
              onClick={() => {
                answer("opened");
                setClosed(true);
                setWriting(true);
              }}
              className={`${buttonClass} sm:flex-1`}
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              data-testid="review-ask-write"
            >
              {t("ask.write")}
            </button>
          ) : null}
          {data.google_review_url ? (
            <a
              href={data.google_review_url}
              target="_blank"
              rel="noreferrer"
              onClick={() => {
                answer("opened");
                setClosed(true);
              }}
              className={`${buttonClass} sm:flex-1`}
              style={outlined}
              data-testid="review-ask-google"
            >
              {t("ask.google")}
            </a>
          ) : null}
          {membership.organization.slug ? (
            <Link
              href={boxChatHref(membership.organization.slug)}
              onClick={() => answer("dismissed")}
              className={`${buttonClass} sm:flex-1`}
              style={outlined}
              data-testid="review-ask-message"
            >
              {t("ask.message")}
            </Link>
          ) : null}
        </div>
      </div>
    </HubCard>
  );
}
