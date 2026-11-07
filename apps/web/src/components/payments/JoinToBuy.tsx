"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { joinToBuy } from "@/api/join-requests";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { boxChatHref } from "@/components/trials/box-chat-links";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { ORGANIZATION_MEMBERSHIPS_KEY } from "@/lib/organization-slug";
import { SPARK_GO_STYLE } from "@/lib/spark";

/**
 * ADR-552: someone who is not a box member yet becomes one by buying (or
 * asking at the desk for) a package the box lists to everyone, whatever the
 * member join link says. Once in, the dialog shows the member checkout.
 */
export function JoinToBuy({ slug, boxName, packageId, desk = false }: { slug: string; boxName: string; packageId: string; desk?: boolean }) {
  const t = useTranslations("Pay");
  const tUi = useUiTranslations();
  const { tokens, rotate } = useSession();
  const queryClient = useQueryClient();
  const join = useMutation({
    mutationFn: () => joinToBuy(tokens!.access_token, slug, packageId),
    onSuccess: async () => {
      // A first membership can change the account role, which retires the old token.
      await rotate().catch(() => undefined);
      await queryClient.invalidateQueries({ queryKey: ORGANIZATION_MEMBERSHIPS_KEY });
    },
  });
  const refused = join.error instanceof ApiError && join.error.payload?.code === "membership_unavailable";

  if (refused) {
    return (
      <div className="flex flex-col gap-3" data-testid="join-to-buy-refused">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("joinToBuyRefused", { box: boxName })}</p>
        <Link
          href={boxChatHref(slug)}
          className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("joinToBuyMessage")}
        </Link>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {desk ? t("joinToHoldBody", { box: boxName }) : t("joinToBuyBody", { box: boxName })}
      </p>
      <button
        type="button"
        disabled={join.isPending}
        onClick={() => join.mutate()}
        className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-extrabold disabled:opacity-50"
        style={SPARK_GO_STYLE}
        data-testid="join-to-buy"
      >
        {t("joinToBuyContinue")}
      </button>
      {join.error ? <ErrorNotice>{clientErrorMessage(join.error, tUi)}</ErrorNotice> : null}
    </div>
  );
}
