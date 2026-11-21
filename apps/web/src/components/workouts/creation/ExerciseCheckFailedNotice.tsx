"use client";

import { useTranslations } from "next-intl";

import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * ADR-671: the exercise check before publishing (ADR-570) could not run. The
 * coach tries again or publishes without it; then only exercises written
 * exactly as the catalog names them count for the muscles and qualities.
 */
export function ExerciseCheckFailedNotice({
  busy,
  onRetry,
  onPublishAnyway,
}: {
  busy: boolean;
  onRetry: () => void;
  onPublishAnyway: () => void;
}) {
  const t = useTranslations("ExerciseMatches");
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-2" data-testid="exercise-check-failed">
      <ErrorNotice variant="text">{t("checkFailed")}</ErrorNotice>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className="min-h-10 rounded-xl px-3 text-sm font-bold disabled:opacity-40"
          style={{ border: "1px solid var(--border)", color: "var(--text)", background: "transparent" }}
          onClick={onRetry}
          disabled={busy}
        >
          {t("retryCheck")}
        </button>
        <button
          type="button"
          className="min-h-10 rounded-xl px-3 text-sm font-bold disabled:opacity-40"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)", background: "transparent" }}
          onClick={onPublishAnyway}
          disabled={busy}
        >
          {t("publishUnchecked")}
        </button>
      </div>
    </div>
  );
}
