"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { FEED_KEY } from "@/api/community";
import { fetchFollowStatus, follow, followKey, SOCIAL_KEY, unfollow, type FollowStatus, type FollowTargetType } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { InlineConfirm } from "@/components/ui/InlineConfirm";

/**
 * Follow a person or a box (plan §5a Q9): «Ακολούθησε» → «Εκκρεμεί» →
 * «Ακολουθείς ✓». A private person approves each request; a public person
 * (ADR-193 §2) and a box are followed at once, so the API answers `active`
 * and the button skips «Εκκρεμεί». It always shows what the API answered.
 * Unfollowing, or withdrawing a request, asks first; unfollowing a Buddy
 * says the Buddy status ends with it. The question is a `ui/InlineConfirm`,
 * so a host row built with `ui/rows` gives it the whole line on a phone.
 */
/** ADR-554: the profile header's short, flat button (Instagram). */
const compactClass = "min-h-8 w-full truncate rounded-lg px-2.5 text-[13px] font-semibold disabled:opacity-50";

export function FollowButton({
  targetType,
  targetId,
  initialStatus,
  followsMe = false,
  buddy = false,
  wide = false,
  quiet = false,
  compact = false,
}: {
  targetType: FollowTargetType;
  targetId: string;
  initialStatus?: FollowStatus;
  followsMe?: boolean;
  buddy?: boolean;
  wide?: boolean;
  /** Outlined instead of filled, where another action is the page's main one. */
  quiet?: boolean;
  /** ADR-554: the profile header's short, flat button (Instagram); fills its grid cell. */
  compact?: boolean;
}) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = followKey(targetType, targetId);
  const status = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    initialData: initialStatus,
    queryFn: () => fetchFollowStatus(token!, targetType, targetId),
  });
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = status.data ?? "none";

  async function run(action: () => Promise<FollowStatus>) {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      queryClient.setQueryData(key, await action());
      setConfirming(false);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: SOCIAL_KEY }),
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      ]);
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setBusy(false);
    }
  }

  const base = compact
    ? `hit-area ${compactClass}`
    : `min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50 ${wide ? "w-full" : ""}`;

  if (confirming) {
    return (
      // In the profile header's two-button row the question takes the whole row.
      <div className={`flex w-full min-w-0 flex-col gap-1 ${wide ? "" : "max-w-md"} ${compact ? "col-span-2" : ""}`}>
        <InlineConfirm
          question={
            current === "requested"
              ? t("withdrawConfirm")
              : targetType === "organization"
                ? t("unfollowBoxConfirm")
                : buddy
                  ? t("unfollowBuddyConfirm")
                  : t("unfollowConfirm")
          }
          cancelLabel={t("keep")}
          confirmLabel={current === "requested" ? t("withdraw") : t("unfollow")}
          busy={busy}
          onCancel={() => setConfirming(false)}
          onConfirm={() => void run(() => unfollow(token!, targetType, targetId))}
        />
        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      </div>
    );
  }

  return (
    <div className={`flex min-w-0 max-w-full flex-col gap-1 ${wide || compact ? "w-full" : ""}`}>
      {current === "none" ? (
        <button
          type="button"
          disabled={busy || !token}
          className={base}
          style={
            quiet
              ? { border: "1px solid var(--border)", color: "var(--text)" }
              : { background: "var(--primary)", color: "var(--primary-contrast)" }
          }
          onClick={() => void run(() => follow(token!, targetType, targetId))}
        >
          {followsMe ? t("followBack") : t("follow")}
        </button>
      ) : (
        <button
          type="button"
          disabled={busy}
          aria-pressed="true"
          className={base}
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: compact ? "none" : "1px solid var(--border)" }}
          onClick={() => setConfirming(true)}
        >
          {current === "requested" ? t("requested") : (
            <span className="inline-flex items-center gap-1.5">
              {t("following")}
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </span>
          )}
        </button>
      )}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}
