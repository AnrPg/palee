"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect } from "react";

import { undoPackageRemoval, type PackageRemoval } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/** How long the toast stays: until the server's undo minute closes (ADR-660). */
export function undoRemainingMs(undoUntil: string, now: number = Date.now()) {
  const until = new Date(undoUntil).getTime();
  return Number.isFinite(until) ? Math.max(until - now, 0) : 0;
}

/**
 * ADR-660: «Το πακέτο αφαιρέθηκε · Αναίρεση». Offered while the removal can
 * still be undone; the member is told only after that.
 */
export function PackageRemovedToast({
  userId,
  nickname,
  removal,
  onDone,
}: {
  userId: string;
  nickname: string;
  removal: PackageRemoval;
  onDone: () => void;
}) {
  const t = useTranslations("PackageRemoval");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();

  useEffect(() => {
    const timer = setTimeout(onDone, undoRemainingMs(removal.undo_until));
    return () => clearTimeout(timer);
  }, [removal.undo_until, onDone]);

  const undo = useMutation({
    mutationFn: () => undoPackageRemoval(tokens?.access_token ?? "", userId, removal.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      onDone();
    },
  });

  return (
    <div
      role="status"
      className="fixed inset-x-0 z-(--z-toast) mx-auto flex w-max max-w-[calc(100vw-2rem)] flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl px-4 py-3 text-sm shadow-lg"
      style={{
        bottom: "max(1rem, env(safe-area-inset-bottom))",
        background: "var(--text)",
        color: "var(--bg)",
      }}
      data-testid="package-removed-toast"
    >
      <span>
        {removal.replacement_package_name
          ? t("changed", { package: removal.package_name, replacement: removal.replacement_package_name, name: nickname })
          : t("removed", { package: removal.package_name, name: nickname })}
      </span>
      <button
        type="button"
        onClick={() => undo.mutate()}
        disabled={undo.isPending}
        className="font-bold underline underline-offset-2 disabled:opacity-50"
        data-testid="package-removed-undo"
      >
        {t("undo")}
      </button>
      {undo.isError ? (
        <ErrorNotice variant="field" className="basis-full">
          {localizeError(undo.error, i18n)}
        </ErrorNotice>
      ) : null}
    </div>
  );
}
