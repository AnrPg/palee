"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { REVIEW_REPORT_REASONS, type BoxReviewReportReason } from "@/api/box-site";
import {
  PLATFORM_REVIEW_REPORTS_KEY,
  REVIEW_STATEMENT_MAX,
  decidePlatformReviewReport,
  fetchPlatformReviewReports,
  restorePlatformReview,
  type PlatformReviewDecision,
  type PlatformReviewReportItem,
  type ReviewReportStatus,
} from "@/api/platform-review-reports";
import { VerifyError } from "@/components/partner-verify/verify-ui";
import { Stars } from "@/components/reviews/ReviewParts";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { withClock } from "@/lib/clock";

const buttonClass = "min-h-10 px-4 text-sm font-semibold disabled:opacity-50";
const textareaClass = "min-h-20 w-full border bg-[var(--panel)] p-3 text-sm text-[var(--text)]";

type Severe = "hide" | "remove";

/**
 * Platform console › «Αναφορές κριτικών» (ADR-397, option A): one card per
 * reported box review, from every box, oldest first, laid out like
 * «Αναφορές Συναθλητών». Who reported stays hidden; only whether a member or
 * the box did. «Μένει» closes the reports; «Απόκρυψη» and «Αφαίρεση» need a
 * ground and the text the author reads. «Αποφασισμένες» lists who decided
 * what and when, and a hidden review can be restored from there with a new
 * statement to its author.
 */
export function PlatformReviewReportsPage() {
  const t = useTranslations("PlatformReviewReports");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [tab, setTab] = useState<ReviewReportStatus>("open");
  const [done, setDone] = useState<string | null>(null);
  const reports = useQuery({
    queryKey: [...PLATFORM_REVIEW_REPORTS_KEY, tab],
    enabled: Boolean(token),
    queryFn: () => fetchPlatformReviewReports(token!, tab),
  });
  const forbidden = reports.error instanceof ApiError && reports.error.status === 403;

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6" data-testid="platform-review-reports">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>
      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {!forbidden ? (
        <div role="tablist" aria-label={t("tabsLabel")} className="mt-6 flex gap-2">
          {(["open", "decided"] as const).map((id) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={tab === id}
              onClick={() => {
                setTab(id);
                setDone(null);
              }}
              className="min-h-11 border border-[var(--border)] text-sm font-semibold text-[var(--text)]"
              data-testid={`review-reports-tab-${id}`}
            >
              {t(`tabs.${id}`)}
            </button>
          ))}
        </div>
      ) : null}
      {reports.error && !forbidden ? <div className="mt-6"><VerifyError error={reports.error} /></div> : null}
      {done ? <p role="status" className="mt-4 text-sm font-semibold text-[var(--success)]">{done}</p> : null}
      {token && reports.data && tab === "open" ? (
        <section className="mt-4 flex flex-col gap-3" aria-label={t("tabs.open")}>
          {reports.data.items.length === 0 ? <p className="text-sm text-[var(--text-soft)]">{t("empty")}</p> : null}
          {reports.data.items.map((item) => (
            <ReportCard key={item.review_id} token={token} item={item} onDone={setDone} />
          ))}
        </section>
      ) : null}
      {token && reports.data && tab === "decided" ? (
        <DecidedList token={token} decisions={reports.data.decisions} onDone={setDone} />
      ) : null}
    </main>
  );
}

function ReportCard({ token, item, onDone }: { token: string; item: PlatformReviewReportItem; onDone: (message: string) => void }) {
  const t = useTranslations("PlatformReviewReports");
  const format = useFormatter();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const groundId = useId();
  const statementId = useId();
  const [severe, setSevere] = useState<Severe | null>(null);
  const [ground, setGround] = useState<BoxReviewReportReason | null>(null);
  const [statement, setStatement] = useState("");
  const [errors, setErrors] = useState<{ ground?: boolean; statement?: boolean }>({});
  const decide = useMutation({
    mutationFn: (outcome: "keep" | Severe) =>
      decidePlatformReviewReport(
        token,
        item.review_id,
        outcome === "keep" ? { outcome, ground: "no_violation", statement: null } : { outcome, ground, statement: statement.trim() },
      ),
    onSuccess: (result) => {
      void queryClient.invalidateQueries({ queryKey: PLATFORM_REVIEW_REPORTS_KEY });
      onDone(t("done", { count: result.resolved }));
    },
  });
  const changed = item.current !== null && (item.current.body !== item.reported.body || item.current.rating !== item.reported.rating);
  const box = item.organization.name ?? "—";
  const author = item.author_name ?? t("anonymous");
  const open = (outcome: Severe) => {
    setSevere(outcome);
    setGround((current) => current ?? topReason(item));
    setErrors({});
  };

  return (
    <article className="flex min-w-0 flex-col gap-3 border border-[var(--border)] bg-[var(--panel)] p-4" data-testid={`review-report-${item.review_id}`}>
      <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate text-base font-semibold text-[var(--text)]">{box} · {author}</p>
          <p className="text-xs text-[var(--text-soft)]">
            {t("count", { count: item.reports_count })} · {t("firstAt", { date: format.dateTime(new Date(item.first_reported_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" })) })}
          </p>
        </div>
        {item.box_reported ? (
          <span className="border border-[var(--border)] bg-[var(--panel-muted)] px-2 py-0.5 text-xs font-semibold text-[var(--warning)]">{t("boxReported")}</span>
        ) : null}
      </div>
      <ReviewText label={changed || item.current === null ? t("reported") : null} rating={item.reported.rating} body={item.reported.body} />
      {item.current === null ? <p className="text-xs text-[var(--dim)]">{t("deleted")}</p> : null}
      {changed && item.current ? <ReviewText label={t("changed")} rating={item.current.rating} body={item.current.body} /> : null}
      <ul className="flex flex-col gap-1 text-sm">
        {item.reasons.map((entry) => (
          <li key={entry.reason} className="font-semibold text-[var(--text)]">
            {reasonLabel(t, entry.reason)} · <span className="tabular-nums">{format.number(entry.count)}</span>
          </li>
        ))}
        {item.notes.map((note) => (
          <li key={`${note.at}-${note.role}`} className="break-words border-t border-[var(--border)] pt-1 text-[var(--text-soft)]">
            {t(`role.${note.role}`)} · «{note.note}»
          </li>
        ))}
      </ul>
      {decide.error ? <DecisionError error={decide.error} /> : null}
      {severe ? (
        <form
          className="flex flex-col gap-2 border border-[var(--border)] bg-[var(--panel-muted)] p-3"
          aria-label={t(`outcome.${severe}`)}
          onSubmit={(event) => {
            event.preventDefault();
            const next = { ground: ground === null, statement: statement.trim().length === 0 };
            setErrors(next);
            if (!next.ground && !next.statement) decide.mutate(severe);
          }}
        >
          <label htmlFor={groundId} className="text-xs font-semibold text-[var(--text-soft)]">{t("ground")}</label>
          <Select
            id={groundId}
            value={ground ?? ""}
            onValueChange={(value) => {
              setGround(value as BoxReviewReportReason);
              setErrors((current) => ({ ...current, ground: false }));
            }}
            placeholder={t("groundPlaceholder")}
            aria-invalid={errors.ground || undefined}
            aria-describedby={errors.ground ? `${groundId}-error` : undefined}
            data-testid="review-decision-ground"
          >
            {REVIEW_REPORT_REASONS.map((reason) => (
              <option key={reason} value={reason}>
                {t(`reasons.${reason}`)} · {t(`basis.${reason === "illegal" ? "law" : "terms"}`)}
              </option>
            ))}
          </Select>
          {errors.ground ? <FieldError id={`${groundId}-error`}>{t("groundRequired")}</FieldError> : null}
          <label htmlFor={statementId} className="text-xs font-semibold text-[var(--text-soft)]">{t("statement")}</label>
          <textarea
            id={statementId}
            className={textareaClass}
            style={{ borderColor: errors.statement ? "var(--danger)" : "var(--border)" }}
            value={statement}
            maxLength={REVIEW_STATEMENT_MAX}
            aria-invalid={errors.statement || undefined}
            aria-describedby={errors.statement ? `${statementId}-error` : `${statementId}-hint`}
            onChange={(event) => {
              setStatement(event.target.value);
              setErrors((current) => ({ ...current, statement: false }));
            }}
            data-testid="review-decision-statement"
          />
          {errors.statement ? (
            <FieldError id={`${statementId}-error`}>{t("statementRequired")}</FieldError>
          ) : (
            <p id={`${statementId}-hint`} className="text-xs text-[var(--dim)]">{t("statementHint")}</p>
          )}
          <div className="flex flex-wrap gap-2">
            <button type="submit" className={`${buttonClass} bg-[var(--danger)] text-[var(--danger-contrast)]`} disabled={decide.isPending} data-testid="review-decision-confirm">
              {t(`confirm.${severe}`)}
            </button>
            <button type="button" className={`${buttonClass} text-[var(--text-soft)]`} disabled={decide.isPending} onClick={() => setSevere(null)}>
              {t("cancel")}
            </button>
          </div>
        </form>
      ) : (
        <div className="flex flex-wrap gap-2">
          <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text)]`} disabled={decide.isPending} onClick={() => decide.mutate("keep")} data-testid="review-decision-keep">
            {t("outcome.keep")}
          </button>
          <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text)]`} disabled={decide.isPending} onClick={() => open("hide")} data-testid="review-decision-hide">
            {t("outcome.hide")}
          </button>
          <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--danger)]`} disabled={decide.isPending} onClick={() => open("remove")} data-testid="review-decision-remove">
            {t("outcome.remove")}
          </button>
        </div>
      )}
    </article>
  );
}

function ReviewText({ label, rating, body }: { label: string | null; rating: number; body: string | null }) {
  const t = useTranslations("PlatformReviewReports");
  return (
    <div className="flex flex-col gap-1">
      {label ? <p className="text-xs font-semibold text-[var(--dim)]">{label}</p> : null}
      <Stars value={rating} size={14} />
      <p className="whitespace-pre-line break-words text-sm text-[var(--text)]">{body ?? t("noText")}</p>
    </div>
  );
}

function DecidedList({ token, decisions, onDone }: { token: string; decisions: PlatformReviewDecision[]; onDone: (message: string) => void }) {
  const t = useTranslations("PlatformReviewReports");
  const format = useFormatter();
  const locale = useLocale();
  const [restoring, setRestoring] = useState<PlatformReviewDecision | null>(null);
  // Newest first: only a review's latest decision offers «Επαναφορά».
  const latest = new Set<string>();
  const restorable = new Set<string>();
  for (const decision of decisions) {
    if (!decision.review_id || latest.has(decision.review_id)) continue;
    latest.add(decision.review_id);
    if (decision.review_status === "hidden" && decision.outcome === "hide") restorable.add(decision.id);
  }

  return (
    <section className="mt-4 flex flex-col gap-3" aria-label={t("tabs.decided")}>
      {decisions.length === 0 ? <p className="text-sm text-[var(--text-soft)]">{t("emptyDecided")}</p> : null}
      {decisions.map((decision) => (
        <article key={decision.id} className="flex min-w-0 flex-col gap-2 border border-[var(--border)] bg-[var(--panel)] p-4" data-testid={`review-decision-${decision.id}`}>
          <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="truncate text-base font-semibold text-[var(--text)]">
                {decision.organization.name ?? "—"} · {t(`outcome.${decision.outcome}`)}
              </p>
              <p className="text-xs text-[var(--text-soft)]">
                {t("by", {
                  name: decision.decided_by ?? "—",
                  date: format.dateTime(new Date(decision.decided_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" })),
                })}
                {decision.reports_count > 0 ? ` · ${t("count", { count: decision.reports_count })}` : ""}
              </p>
            </div>
            <span className="border border-[var(--border)] bg-[var(--panel-muted)] px-2 py-0.5 text-xs font-semibold text-[var(--text-soft)]">
              {t(`status.${decision.review_status}`)}
            </span>
          </div>
          <p className="text-sm font-semibold text-[var(--text)]">{reasonLabel(t, decision.ground)}</p>
          {decision.statement ? <p className="whitespace-pre-line break-words text-sm text-[var(--text-soft)]">«{decision.statement}»</p> : null}
          {restorable.has(decision.id) ? (
            <button type="button" className={`${buttonClass} self-start border border-[var(--border)] text-[var(--text)]`} onClick={() => setRestoring(decision)} data-testid="review-restore">
              {t("restore")}
            </button>
          ) : null}
        </article>
      ))}
      {restoring?.review_id ? (
        <RestoreDialog
          token={token}
          reviewId={restoring.review_id}
          onClose={() => setRestoring(null)}
          onDone={() => {
            setRestoring(null);
            onDone(t("restored"));
          }}
        />
      ) : null}
    </section>
  );
}

function RestoreDialog({ token, reviewId, onClose, onDone }: { token: string; reviewId: string; onClose: () => void; onDone: () => void }) {
  const t = useTranslations("PlatformReviewReports");
  const queryClient = useQueryClient();
  const statementId = useId();
  const [statement, setStatement] = useState("");
  const [missing, setMissing] = useState(false);
  const restore = useMutation({
    mutationFn: () => restorePlatformReview(token, reviewId, statement.trim()),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: PLATFORM_REVIEW_REPORTS_KEY });
      onDone();
    },
  });
  return (
    <Dialog
      onClose={onClose}
      title={t("restoreTitle")}
      description={t("restoreHint")}
      size="md"
      testId="review-restore-dialog"
      dismissible={!restore.isPending}
      onSubmit={() => {
        const empty = statement.trim().length === 0;
        setMissing(empty);
        if (!empty) restore.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold text-[var(--text-soft)]">
            {t("cancel")}
          </button>
          <button type="submit" disabled={restore.isPending} className="min-h-11 rounded-2xl bg-[var(--primary)] px-5 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-60" data-testid="review-restore-confirm">
            {t("restoreTitle")}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-2">
        {restore.error ? <DecisionError error={restore.error} /> : null}
        <label htmlFor={statementId} className="text-sm font-semibold text-[var(--text)]">{t("statement")}</label>
        <textarea
          id={statementId}
          className={textareaClass}
          style={{ borderColor: missing ? "var(--danger)" : "var(--border)" }}
          value={statement}
          maxLength={REVIEW_STATEMENT_MAX}
          aria-invalid={missing || undefined}
          aria-describedby={missing ? `${statementId}-error` : undefined}
          onChange={(event) => {
            setStatement(event.target.value);
            setMissing(false);
          }}
          data-testid="review-restore-statement"
        />
        {missing ? <FieldError id={`${statementId}-error`}>{t("statementRequired")}</FieldError> : null}
      </div>
    </Dialog>
  );
}

function DecisionError({ error }: { error: unknown }) {
  const t = useTranslations("PlatformReviewReports");
  if (error instanceof ApiError && ["review_report_decided", "review_not_hidden"].includes(String(error.payload.code))) {
    return <ErrorNotice>{t("alreadyDecided")}</ErrorNotice>;
  }
  return <VerifyError error={error} />;
}

/** The reason reported most, as the ground to start from. */
export function topReason(item: Pick<PlatformReviewReportItem, "reasons">): BoxReviewReportReason | null {
  const known = item.reasons.filter((entry) => (REVIEW_REPORT_REASONS as string[]).includes(entry.reason));
  if (known.length === 0) return null;
  return known.reduce((best, entry) => (entry.count > best.count ? entry : best)).reason as BoxReviewReportReason;
}

function reasonLabel(t: ReturnType<typeof useTranslations<"PlatformReviewReports">>, reason: string) {
  if (reason === "no_violation") return t("noViolation");
  return (REVIEW_REPORT_REASONS as string[]).includes(reason) ? t(`reasons.${reason as BoxReviewReportReason}`) : reason;
}
