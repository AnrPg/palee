"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import { answerWatchOffer, requestWatchOffer } from "@/api/body-devices";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { startOnWatch, watchStatus, type WatchPlatform } from "@/lib/platform/watch";

/**
 * «Το χρονόμετρο και στο ρολόι;» (ADR-375 amendment, ANR's D8 rules): only
 * here, when a WOD is opened for execution, and only when the phone sees a
 * connected watch at this moment. The server decides (`watch-offer`): ask,
 * start on its own (box members after their first five WODs) or nothing
 * (class WOD without check-in, …). Never a notification. On the web and in
 * store apps without the watch plugin it renders nothing.
 */
export function WatchOfferPrompt({ executionId }: { executionId: string }) {
  const t = useTranslations("BodyDevices");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [asking, setAsking] = useState<WatchPlatform | null>(null);
  const [answering, setAnswering] = useState(false);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    void (async () => {
      const status = await watchStatus();
      if (!status || !status.connected || cancelled) return;
      try {
        const offer = await requestWatchOffer(token, executionId, status.platform, true);
        if (cancelled) return;
        if (offer.mode === "start") await startOnWatch(executionId);
        if (offer.mode === "ask") setAsking(status.platform);
      } catch {
        // No offer when the server cannot be asked: the phone timer runs as usual.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [executionId, token]);

  if (!asking || !token) return null;

  async function answer(choice: "yes" | "no") {
    setAnswering(true);
    try {
      const result = await answerWatchOffer(token!, executionId, choice);
      if (result.mode === "start") await startOnWatch(executionId);
    } catch {
      // The answer is asked again next time the WOD opens.
    } finally {
      setAsking(null);
      setAnswering(false);
    }
  }

  return (
    <Dialog
      onClose={() => void answer("no")}
      title={t("watch.offerTitle")}
      description={t(`watch.offerFound.${asking}`)}
      titleId={`watch-offer-${executionId}`}
      variant="sheet"
      size="sm"
      testId="watch-offer"
      footer={
        <div className="flex w-full flex-col gap-2">
          <button
            type="button"
            disabled={answering}
            onClick={() => void answer("yes")}
            className="min-h-11 rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("watch.offerYes")}
          </button>
          <button
            type="button"
            disabled={answering}
            onClick={() => void answer("no")}
            className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
            style={{ color: "var(--text-soft)" }}
          >
            {t("watch.offerNo")}
          </button>
        </div>
      }
    >
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("watch.offerShows")}</p>
    </Dialog>
  );
}
