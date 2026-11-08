"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import { askToJoin, cancelJoinRequest, fetchMyJoinRequest, myJoinRequestKey, type MyJoinRequest } from "@/api/join-requests";
import type { PublicBoxPage } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useBoxSales } from "@/components/payments/BoxSales";
import { useSession } from "@/components/session-provider";
import { boxChatHref } from "@/components/trials/box-chat-links";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { SPARK_GO_STYLE } from "@/lib/spark";

import { joinBoxTarget } from "./join-box";

const MAIN = "flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl px-4 text-base font-extrabold";

/** «Γίνε μέλος box» (ADR-552): a link, or «Ζήτα να γίνεις μέλος» with its own sheet. */
export function JoinBoxAction({ page, signedIn }: { page: PublicBoxPage; signedIn: boolean }) {
  const t = useTranslations("BoxPage");
  const sales = useBoxSales(signedIn ? page.box.slug : null);
  const target = joinBoxTarget(page, signedIn, signedIn ? sales.shownCount : null);
  if (target.kind === "link") {
    return (
      <Link href={target.href} className={MAIN} style={SPARK_GO_STYLE} data-testid="box-page-join">
        {t("joinBox")}
      </Link>
    );
  }
  return <AskToJoin page={page} />;
}

function AskToJoin({ page }: { page: PublicBoxPage }) {
  const t = useTranslations("BoxPage");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = page.box.slug;
  const [open, setOpen] = useState(false);
  // Back from signing in with «Γίνε μέλος box» pressed (`?join=1`): the sheet
  // opens once. The page renders this button twice (side card, phone bar);
  // the first to run takes the link, like the trial button.
  useEffect(() => {
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams(window.location.search);
      if (params.get("join") !== "1") return;
      params.delete("join");
      const query = params.toString();
      window.history.replaceState(null, "", window.location.pathname + (query ? `?${query}` : "") + window.location.hash);
      setOpen(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);
  const mine = useQuery({
    queryKey: myJoinRequestKey(slug),
    queryFn: () => fetchMyJoinRequest(token, slug).then((response) => response.request),
    enabled: Boolean(token),
  });
  const waiting = mine.data?.status === "requested";

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={MAIN} style={SPARK_GO_STYLE} data-testid="box-page-join">
        {waiting ? t("joinWaiting") : t("joinBox")}
      </button>
      {open ? <AskSheet page={page} request={mine.data ?? null} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function AskSheet({ page, request, onClose }: { page: PublicBoxPage; request: MyJoinRequest | null; onClose: () => void }) {
  const t = useTranslations("BoxPage");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = page.box.slug;
  const queryClient = useQueryClient();
  const settle = (response: { request: MyJoinRequest }) => queryClient.setQueryData(myJoinRequestKey(slug), response.request);
  const ask = useMutation({ mutationFn: () => askToJoin(token, slug), onSuccess: settle });
  const cancel = useMutation({ mutationFn: () => cancelJoinRequest(token, slug), onSuccess: settle });
  const error = ask.error ?? cancel.error;
  const status = request?.status ?? null;

  return (
    <Dialog onClose={onClose} title={t("joinAskTitle", { box: page.box.name })} size="sm" variant="sheet" testId="box-join-ask">
      <div className="flex min-w-0 flex-col gap-3">
        {status === "requested" ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("joinSentBody", { box: page.box.name })}</p>
            <span
              className="self-start rounded-full px-3 py-1 text-xs font-bold"
              style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}
              data-testid="box-join-pending"
            >
              {t("joinWaiting")}
            </span>
            <button
              type="button"
              disabled={cancel.isPending}
              onClick={() => cancel.mutate()}
              className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("joinCancel")}
            </button>
          </>
        ) : (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {status === "declined" ? t("joinDeclinedBody", { box: page.box.name }) : t("joinAskBody", { box: page.box.name })}
            </p>
            <button
              type="button"
              disabled={ask.isPending}
              onClick={() => ask.mutate()}
              className="min-h-11 rounded-2xl px-4 text-sm font-extrabold disabled:opacity-50"
              style={SPARK_GO_STYLE}
              data-testid="box-join-send"
            >
              {status === "declined" ? t("joinAskAgain") : t("joinSend")}
            </button>
            <Link
              href={boxChatHref(slug)}
              className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("messageBox")}
            </Link>
          </>
        )}
        {error ? <ErrorNotice>{clientErrorMessage(error, tUi)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
