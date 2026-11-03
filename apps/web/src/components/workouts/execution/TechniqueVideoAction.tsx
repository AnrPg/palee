"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { FORM_REVIEWS_KEY, FormReviewForm } from "@/components/client/CoachingConsole";
import { allowanceRemaining, hasCapability } from "@/components/client/entitlement";
import { CLIENT_ENTITLEMENT_QUERY_KEY, useClientEntitlement } from "@/components/client/use-client-entitlement";
import { Dialog } from "@/components/ui/Dialog";

/**
 * ANR mockup d5 A: «Στείλε βίντεο τεχνικής στον coach» on the completion
 * screen, tied to the run just done (FormReview `execution_id`, ADR-098). A
 * quiet secondary button, only when the package includes technique videos
 * and some are left; the coach sees it in their queue as before.
 */
export function TechniqueVideoAction({ executionId }: { executionId: string }) {
  const t = useTranslations("TrainingFloor");
  const queryClient = useQueryClient();
  const { entitlement } = useClientEntitlement();
  const [open, setOpen] = useState(false);
  const [sent, setSent] = useState(false);
  const allowance = allowanceRemaining(entitlement, "form_reviews");

  if (!hasCapability(entitlement, "request_form_reviews")) return null;
  if (allowance && allowance.remaining !== "unlimited" && allowance.remaining <= 0) return null;

  if (sent) {
    return (
      <p role="status" className="text-center text-sm" style={{ color: "var(--success)" }}>
        {t("videoSent")}
      </p>
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="w-full rounded-2xl py-3 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid="technique-video"
      >
        {t("videoSend")}
      </button>
      {allowance && allowance.remaining !== "unlimited" ? (
        <p className="text-center text-xs" style={{ color: "var(--dim)" }}>
          {t("videoLeft", { count: allowance.remaining })}
        </p>
      ) : null}
      {open ? (
        <Dialog onClose={() => setOpen(false)} title={t("videoSend")} titleId="technique-video-title" size="md">
          <FormReviewForm
            executionId={executionId}
            onSubmitted={() => {
              void queryClient.invalidateQueries({ queryKey: FORM_REVIEWS_KEY });
              void queryClient.invalidateQueries({ queryKey: CLIENT_ENTITLEMENT_QUERY_KEY });
              setOpen(false);
              setSent(true);
            }}
          />
        </Dialog>
      ) : null}
    </>
  );
}
