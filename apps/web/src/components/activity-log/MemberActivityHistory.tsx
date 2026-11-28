"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import { activityLogKeys, fetchMyActivity } from "@/api/activity-log";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

import { shownReason } from "./activity-log-model";

const SHORT = 3;

/**
 * Box › Συνδρομή › Ιστορικό (ADR-760, 5A): what the box chose to share with
 * the member («Να το δει και το μέλος»). Who on the staff did it is never
 * shown: every row reads «Το box». Hidden while there is nothing to show.
 */
export function MemberActivityHistory({ slug }: { slug: string }) {
  const t = useTranslations("ActivityLog");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone(slug);
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [expanded, setExpanded] = useState(false);

  const history = useInfiniteQuery({
    queryKey: activityLogKeys.mine(slug),
    enabled: Boolean(token),
    staleTime: FRESHNESS.live,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchMyActivity(token!, slug, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const entries = useMemo(() => (history.data?.pages ?? []).flatMap((page) => page.entries ?? []), [history.data]);
  if (entries.length === 0) return null;

  const shown = expanded ? entries : entries.slice(0, SHORT);
  const day = new Intl.DateTimeFormat(locale, { day: "numeric", month: "numeric", ...(zone ? { timeZone: zone } : {}) });
  const more = !expanded ? entries.length > SHORT || history.hasNextPage : history.hasNextPage;

  return (
    <section className="flex flex-col gap-2" data-testid="member-activity">
      <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("historyTitle")}</h3>
      <ul className="flex flex-col gap-2">
        {shown.map((entry) => {
          const reason = shownReason(entry);
          return (
            <li key={entry.id} className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }} data-testid="member-activity-entry">
              <span className="block text-xs" style={{ color: "var(--dim)" }}>
                {day.format(new Date(entry.occurred_at))} · {t("theBox")}
              </span>
              <span className="block">
                {t(`actions.${entry.action}`)}
                {entry.subject_label ? ` «${entry.subject_label}»` : ""}
              </span>
              {reason ? <span className="block text-xs" style={{ color: "var(--text-soft)" }}>{t("reasonShown", { reason })}</span> : null}
            </li>
          );
        })}
      </ul>
      {more ? (
        <button
          type="button"
          className="self-start text-sm font-semibold disabled:opacity-60"
          style={{ color: "var(--primary)" }}
          disabled={history.isFetchingNextPage}
          onClick={() => {
            if (expanded || entries.length <= SHORT) void history.fetchNextPage();
            setExpanded(true);
          }}
          data-testid="member-activity-more"
        >
          {t("more")}
        </button>
      ) : null}
    </section>
  );
}
