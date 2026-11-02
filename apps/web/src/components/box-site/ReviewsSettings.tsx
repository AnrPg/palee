"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  fetchStaffBoxReviews,
  getReviewAskSettings,
  getReviewAskSummary,
  replyToBoxReview,
  saveReviewAskSettings,
  searchGooglePlaces,
  STAFF_BOX_REVIEWS_KEY,
  type BoxReview,
  type ReviewAskSettingsResponse,
  type ReviewAskSettingsUpdate,
} from "@/api/box-site";
import { GoogleReviews, ReviewItem, ReviewSummary } from "@/components/reviews/ReviewParts";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { SettingsEntry } from "./WebsiteSettings";

const SETTINGS_KEY = ["admin", "review-asks", "settings"] as const;
const SUMMARY_KEY = ["admin", "review-asks", "summary"] as const;

/**
 * Ρυθμίσεις › Κριτικές (ADR-386, ADR-387; ANR s6, s7): the box's Google
 * listing found by name (Place ID as the fallback), the ask after the 10th,
 * 50th and 100th class, and the members' reviews with the box's replies.
 * The box replies; it cannot delete a review.
 */
export function ReviewsSettings() {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: SETTINGS_KEY, enabled: Boolean(token), queryFn: () => getReviewAskSettings(token) });
  const summary = useQuery({ queryKey: SUMMARY_KEY, enabled: Boolean(token), queryFn: () => getReviewAskSummary(token), retry: false });
  const save = useMutation({
    mutationFn: (update: Omit<ReviewAskSettingsUpdate, "lock_version">) => saveReviewAskSettings(token, { ...update, lock_version: settings.data!.settings.lock_version }),
    onSuccess: (data) => queryClient.setQueryData<ReviewAskSettingsResponse>(SETTINGS_KEY, data),
  });
  const saveError = save.error instanceof ApiError && save.error.status === 409 ? t("settings.stale") : save.error ? localizeError(save.error, ui) : null;
  const current = settings.data?.settings;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }} data-testid="reviews-settings">
      <div className="mx-auto flex max-w-3xl flex-col gap-5">
        <header className="flex flex-col gap-2">
          <Link href={adminHref("/admin/settings", slug)} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            ‹ {t("settings.back")}
          </Link>
          <h1 className="text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("title")}</h1>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settings.intro")}</p>
        </header>

        {settings.isPending ? <StatusText tone="muted">{t("settings.loading")}</StatusText> : null}
        {settings.isError ? <StatusText tone="error">{localizeError(settings.error, ui)}</StatusText> : null}
        {saveError ? <StatusText tone="error">{saveError}</StatusText> : null}

        {settings.data && current ? (
          <>
            <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="reviews-google">
              <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("settings.googleTitle")}</h2>
              {settings.data.google ? (
                <>
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{settings.data.google.name}</p>
                  <GoogleReviews google={settings.data.google} />
                </>
              ) : current.google_place_id ? (
                <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("settings.googleWaiting")}</p>
              ) : (
                <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settings.googleHint")}</p>
              )}
              <PlaceFinder token={token} disabled={save.isPending} onPick={(placeId) => save.mutate({ google_place_id: placeId })} />
              {current.google_place_id ? (
                <button type="button" onClick={() => save.mutate({ google_place_id: null })} className="self-start text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
                  {t("settings.unlink")}
                </button>
              ) : null}
              <AdvancedDisclosure testId="reviews-advanced">
                <PlaceIdField initial={current.google_place_id ?? ""} disabled={save.isPending} onSave={(placeId) => save.mutate({ google_place_id: placeId || null })} />
              </AdvancedDisclosure>
            </section>

            <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="reviews-ask">
              <label className="flex min-h-11 items-center justify-between gap-3">
                <span className="flex flex-col">
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.askTitle")}</span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.askHint")}</span>
                </span>
                <input
                  type="checkbox"
                  role="switch"
                  checked={current.enabled}
                  disabled={save.isPending}
                  onChange={(event) => save.mutate({ enabled: event.target.checked })}
                  className="h-5 w-5 shrink-0"
                  style={{ accentColor: "var(--primary)" }}
                  data-testid="reviews-ask-switch"
                />
              </label>
              {summary.data ? (
                <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="reviews-ask-summary">
                  {t("settings.askSummary", { asked: summary.data.counts.asked, opened: summary.data.counts.opened, days: summary.data.days })}
                </p>
              ) : null}
            </section>

            <MemberReviews token={token} />
          </>
        ) : null}
      </div>
    </main>
  );
}

function PlaceFinder({ token, disabled, onPick }: { token: string; disabled: boolean; onPick: (placeId: string) => void }) {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const [query, setQuery] = useState("");
  const search = useMutation({ mutationFn: () => searchGooglePlaces(token, query.trim()) });
  const invalid = search.error instanceof ApiError && search.error.status === 422;
  return (
    <div className="flex flex-col gap-2">
      <form
        className="flex gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (query.trim().length >= 3) search.mutate();
        }}
      >
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("settings.searchPlaceholder")}
          aria-label={t("settings.searchLabel")}
          aria-invalid={invalid || undefined}
          aria-describedby={invalid ? "reviews-place-error" : undefined}
          className={inputClass}
          style={{ ...inputStyle, ...(invalid ? { borderColor: "var(--danger)" } : {}) }}
          data-testid="reviews-place-search"
        />
        <button type="submit" disabled={search.isPending || query.trim().length < 3} className={`${secondaryButtonClass} shrink-0`} style={secondaryButtonStyle}>
          {t("settings.search")}
        </button>
      </form>
      {invalid ? <FieldError id="reviews-place-error">{t("settings.searchTooShort")}</FieldError> : null}
      {search.error && !invalid ? <StatusText tone="error">{search.error instanceof ApiError && search.error.status === 503 ? t("settings.googleDown") : localizeError(search.error, ui)}</StatusText> : null}
      {search.data ? (
        search.data.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("settings.noPlaces")}</p>
        ) : (
          <ul className="flex flex-col gap-2" data-testid="reviews-place-results">
            {search.data.map((place) => (
              <li key={place.place_id}>
                <button
                  type="button"
                  disabled={disabled}
                  onClick={() => onPick(place.place_id)}
                  className="flex w-full flex-col items-start gap-0.5 rounded-2xl px-4 py-3 text-start"
                  style={{ border: "1px solid var(--border)" }}
                >
                  <b className="text-sm" style={{ color: "var(--text)" }}>{place.name}</b>
                  {place.address ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{place.address}</span> : null}
                  {place.rating != null ? (
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      ★ {place.rating} · {t("googleCount", { count: place.rating_count ?? 0 })}
                    </span>
                  ) : null}
                </button>
              </li>
            ))}
          </ul>
        )
      ) : null}
    </div>
  );
}

function PlaceIdField({ initial, disabled, onSave }: { initial: string; disabled: boolean; onSave: (placeId: string) => void }) {
  const t = useTranslations("BoxReviews");
  const [value, setValue] = useState(initial);
  return (
    <form
      className="flex flex-col gap-1.5"
      onSubmit={(event) => {
        event.preventDefault();
        onSave(value.trim());
      }}
    >
      <label htmlFor="reviews-place-id" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.placeId")}</label>
      <span className="text-xs" style={{ color: "var(--muted)" }}>{t("settings.placeIdHint")}</span>
      <div className="flex gap-2">
        <input id="reviews-place-id" value={value} maxLength={300} onChange={(event) => setValue(event.target.value)} className={inputClass} style={inputStyle} />
        <button type="submit" disabled={disabled || value.trim() === initial} className={`${secondaryButtonClass} shrink-0`} style={secondaryButtonStyle}>
          {t("settings.savePlaceId")}
        </button>
      </div>
    </form>
  );
}

function MemberReviews({ token }: { token: string }) {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const reviews = useQuery({ queryKey: STAFF_BOX_REVIEWS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffBoxReviews(token) });
  const [replying, setReplying] = useState<BoxReview | null>(null);
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="reviews-members">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("settings.membersTitle")}</h2>
      {reviews.isError ? <StatusText tone="error">{localizeError(reviews.error, ui)}</StatusText> : null}
      {reviews.data ? (
        reviews.data.count === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settings.noReviews")}</p>
        ) : (
          <>
            <ReviewSummary average={reviews.data.average} count={reviews.data.count} />
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.noDelete")}</p>
            <div className="flex flex-col gap-3">
              {reviews.data.reviews.map((review) => (
                <div key={review.id} className="flex flex-col gap-1">
                  <ul>
                    <ReviewItem review={review} boxName={t("settings.theBox")} />
                  </ul>
                  <button type="button" onClick={() => setReplying(review)} className="self-end text-sm font-bold" style={{ color: "var(--primary-strong)" }} data-testid="reviews-reply">
                    {review.reply ? t("settings.editReply") : t("settings.reply")}
                  </button>
                </div>
              ))}
            </div>
          </>
        )
      ) : null}
      {replying ? <ReplyDialog token={token} review={replying} onClose={() => setReplying(null)} /> : null}
    </section>
  );
}

function ReplyDialog({ token, review, onClose }: { token: string; review: BoxReview; onClose: () => void }) {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const [body, setBody] = useState(review.reply?.body ?? "");
  const [empty, setEmpty] = useState(false);
  const send = useMutation({
    mutationFn: () => replyToBoxReview(token, review.id, body.trim()),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: STAFF_BOX_REVIEWS_KEY });
      onClose();
    },
  });
  return (
    <Dialog
      onClose={onClose}
      title={t("settings.replyTitle")}
      size="md"
      testId="reviews-reply-dialog"
      dismissible={!send.isPending}
      onSubmit={() => {
        setEmpty(!body.trim());
        if (body.trim()) send.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button type="submit" disabled={send.isPending} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("settings.sendReply")}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-2">
        {review.body ? <p className="text-sm italic" style={{ color: "var(--text-soft)" }}>{review.body}</p> : null}
        <textarea
          value={body}
          onChange={(event) => setBody(event.target.value)}
          rows={4}
          maxLength={2000}
          aria-label={t("settings.replyTitle")}
          aria-invalid={empty || undefined}
          aria-describedby={empty ? "reviews-reply-error" : undefined}
          className={inputClass}
          style={{ ...inputStyle, ...(empty ? { borderColor: "var(--danger)" } : {}) }}
        />
        {empty ? <FieldError id="reviews-reply-error">{t("settings.replyRequired")}</FieldError> : null}
        {send.error ? <StatusText tone="error">{localizeError(send.error, ui)}</StatusText> : null}
      </div>
    </Dialog>
  );
}

/** Ρυθμίσεις › «Κριτικές» entry. */
export function ReviewsSettingsLink() {
  const t = useTranslations("BoxReviews");
  const slug = useOrganizationSlug();
  return <SettingsEntry href={adminHref("/admin/settings/reviews", slug)} title={t("title")} hint={t("settings.navHint")} testId="reviews-settings-link" />;
}
