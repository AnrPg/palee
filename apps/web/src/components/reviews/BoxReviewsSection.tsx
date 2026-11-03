"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { deleteMyBoxReview, fetchMyBoxReviews, MY_BOX_REVIEWS_KEY } from "@/api/box-site";
import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { GoogleReviews, ReviewItem, ReviewSummary } from "./ReviewParts";
import { ReviewSheet } from "./ReviewSheet";

/**
 * «Κριτικές» in Box (ADR-386): the members' reviews with the box's replies,
 * «Η κριτική μου» to write, edit or delete, and Google's rating apart.
 * Only people who checked in may write, one review each.
 */
export function BoxReviewsSection({ membership }: BoxExtensionProps) {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const reviews = useQuery({ queryKey: [...MY_BOX_REVIEWS_KEY, membership.organization.id], enabled: Boolean(token), queryFn: () => fetchMyBoxReviews(token) });
  const [writing, setWriting] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const remove = useMutation({
    mutationFn: () => deleteMyBoxReview(token),
    onSuccess: () => {
      setConfirmDelete(false);
      void queryClient.invalidateQueries({ queryKey: MY_BOX_REVIEWS_KEY });
    },
  });
  const data = reviews.data;
  if (!data || !Array.isArray(data.reviews)) return null;
  if (data.count === 0 && !data.can_review && !data.google) return null;
  const box = membership.organization.name;
  const others = data.reviews.filter((review) => review.id !== data.mine?.id);

  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="box-reviews">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t("title")}</h2>
        {data.can_review && !data.mine ? (
          <button type="button" onClick={() => setWriting(true)} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} data-testid="box-reviews-write">
            {t("write")}
          </button>
        ) : null}
      </div>
      <ReviewSummary average={data.average} count={data.count} testId="box-reviews-average" />
      {data.mine ? (
        <div className="flex flex-col gap-1" data-testid="box-reviews-mine">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("mine")}</span>
            <MoreMenu
              label={t("mineMenu")}
              items={[
                { label: t("edit"), onSelect: () => setWriting(true), testId: "box-reviews-edit" },
                { label: t("delete"), tone: "danger", onSelect: () => setConfirmDelete(true), testId: "box-reviews-delete" },
              ]}
            />
          </div>
          <ul>
            <ReviewItem review={data.mine} boxName={box} />
          </ul>
        </div>
      ) : null}
      {others.length > 0 ? (
        <ul className="flex flex-col gap-3">
          {others.map((review) => (
            <ReviewItem key={review.id} review={review} boxName={box} />
          ))}
        </ul>
      ) : null}
      {data.google ? <GoogleReviews google={data.google} /> : null}
      {remove.error ? <StatusText tone="error">{localizeError(remove.error, ui)}</StatusText> : null}
      {writing ? <ReviewSheet token={token} boxName={box} mine={data.mine ?? null} onClose={() => setWriting(false)} /> : null}
      {confirmDelete ? (
        <Dialog
          onClose={() => setConfirmDelete(false)}
          title={t("deleteTitle")}
          size="sm"
          testId="box-reviews-delete-dialog"
          footer={
            <>
              <button type="button" onClick={() => setConfirmDelete(false)} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
                {t("cancel")}
              </button>
              <button type="button" disabled={remove.isPending} onClick={() => remove.mutate()} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
                {t("delete")}
              </button>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("deleteText")}</p>
        </Dialog>
      ) : null}
    </section>
  );
}
