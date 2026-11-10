"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { decideJoinRequest, fetchStaffJoinRequests, STAFF_JOIN_REQUESTS_KEY, type StaffJoinRequest } from "@/api/join-requests";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { SPARK_GO_STYLE } from "@/lib/spark";

/**
 * ADR-552: Μέλη › «Θέλουν να γίνουν μέλη». People who asked to become box
 * members while the member join link is off; accept or decline each. Shown
 * only while someone waits (an empty card is never shown).
 */
export function JoinRequestsCard({ onAccepted }: { onAccepted?: () => void }) {
  const t = useTranslations("UsersDirectory");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const requests = useQuery({
    queryKey: STAFF_JOIN_REQUESTS_KEY,
    queryFn: () => fetchStaffJoinRequests(token),
    enabled: Boolean(token),
  });
  const rows = requests.data ?? [];
  if (rows.length === 0) return null;

  return (
    <section
      aria-labelledby="join-requests-title"
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="join-requests"
    >
      <h2 id="join-requests-title" className="text-base font-bold" style={{ color: "var(--text)" }}>
        {t("joinRequestsTitle", { count: rows.length })}
      </h2>
      <ul className="flex flex-col gap-2">
        {rows.map((request) => (
          <JoinRequestRow key={request.id} request={request} onAccepted={onAccepted} />
        ))}
      </ul>
    </section>
  );
}

function JoinRequestRow({ request, onAccepted }: { request: StaffJoinRequest; onAccepted?: () => void }) {
  const t = useTranslations("UsersDirectory");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const decide = useMutation({
    mutationFn: (decision: "accept" | "decline") => decideJoinRequest(tokens!.access_token, request.id, decision),
    onSuccess: async (_response, decision) => {
      await queryClient.invalidateQueries({ queryKey: STAFF_JOIN_REQUESTS_KEY });
      if (decision === "accept") onAccepted?.();
    },
  });
  const name = request.person?.nickname ?? t("joinRequestsSomeone");
  const asked = new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(request.requested_at));

  return (
    <li className="flex flex-col gap-2 rounded-xl p-3 sm:flex-row sm:items-center" style={{ background: "var(--panel-muted)" }}>
      <span className="flex min-w-0 flex-1 items-center gap-3">
        <PersonAvatar name={name} url={request.person?.avatar_url} size={36} />
        <span className="min-w-0">
          <span className="block truncate text-sm font-bold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[request.person?.handle ? `@${request.person.handle}` : null, t("joinRequestsAsked", { date: asked })].filter(Boolean).join(" · ")}
          </span>
        </span>
      </span>
      <span className="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          disabled={decide.isPending}
          onClick={() => decide.mutate("decline")}
          className="min-h-10 flex-1 rounded-xl px-3 text-sm font-semibold disabled:opacity-50 sm:flex-none"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          aria-label={t("joinRequestsDeclineNamed", { name })}
        >
          {t("joinRequestsDecline")}
        </button>
        <button
          type="button"
          disabled={decide.isPending}
          onClick={() => decide.mutate("accept")}
          className="min-h-10 flex-1 rounded-xl px-3 text-sm font-bold disabled:opacity-50 sm:flex-none"
          style={SPARK_GO_STYLE}
          aria-label={t("joinRequestsAcceptNamed", { name })}
        >
          {t("joinRequestsAccept")}
        </button>
      </span>
      {decide.error ? <ErrorNotice>{clientErrorMessage(decide.error, tUi)}</ErrorNotice> : null}
    </li>
  );
}
