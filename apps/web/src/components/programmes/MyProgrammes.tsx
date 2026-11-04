"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useId, useMemo, useState } from "react";

import { doProgrammeDayToday, fetchProgrammeDays, programmeDaysKey, skipProgrammeDay } from "@/api/programme-days";
import {
  fetchMyProgramme,
  fetchMyProgrammes,
  myProgrammeKey,
  myProgrammesKey,
  reviewProgramme,
  withdrawProgramme,
  type ProgrammePurchase,
} from "@/api/programmes";
import { HubCard } from "@/components/member-app/HubParts";
import { dangerButtonStyle } from "@/components/staff/staff-ui";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";
import { dateKeyInZone } from "@/lib/zoned-time";

import { readDays } from "./programme-day-model";
import { programmeDayOf, programmeProgress, utcDay } from "./programme-grid";
import { ProgrammeDayBoard } from "./ProgrammeDayBoard";
import { programmeMoney, useProgrammeError } from "./programme-ui";

function useToday() {
  const zone = useOrganizationTimeZone();
  return dateKeyInZone(new Date(), zone);
}

/**
 * Box › Σήμερα (mockup W8 s6 A): the programme's WODs are already in the
 * day like any other WOD; this card names where the member is in each
 * programme they bought, with «Λεπτομέρειες» for the rest.
 */
export function MyProgrammesCard() {
  const t = useTranslations("Programmes");
  const token = useSession().tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const today = useToday();
  const locale = useLocale();
  const purchases = useQuery({
    queryKey: myProgrammesKey(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchMyProgrammes(token!, slug!),
    staleTime: 60_000,
  });
  const active = (purchases.data ?? []).filter((purchase) => purchase.status === "active");
  if (active.length === 0) return null;

  return (
    <HubCard eyebrow={t("myProgrammes")}>
      <ul className="flex flex-col gap-3" data-testid="my-programmes">
        {active.map((purchase) => {
          const where = programmeDayOf(purchase.starts_on, today);
          const progress = programmeProgress(purchase.starts_on, purchase.ends_on, today);
          const started = purchase.starts_on <= today;
          return (
            <li key={purchase.id} className="flex min-w-0 items-center gap-3">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{purchase.title ?? t("title")}</p>
                <p className="text-xs" style={{ color: "var(--muted)" }}>
                  {started && where ? t("weekDay", { week: where.week, day: where.day }) : t("startsOnDate", { date: new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" }).format(utcDay(purchase.starts_on)) })}
                  {" · "}
                  {t("daysProgress", { done: progress.done, total: progress.total })}
                </p>
                <div className="mt-1 h-1.5 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }} aria-hidden="true">
                  <div className="h-full rounded-full" style={{ width: `${Math.round((progress.done / progress.total) * 100)}%`, background: "var(--primary)" }} />
                </div>
              </div>
              <Link href={`/box/programmes/${encodeURIComponent(purchase.id)}`} className="shrink-0 text-sm font-semibold" style={{ color: "var(--primary-strong)" }} data-testid={`my-programme-${purchase.id}`}>
                {t("details")} ›
              </Link>
            </li>
          );
        })}
      </ul>
    </HubCard>
  );
}

/**
 * A bought programme (board 3κ/3μ A): «Η μέρα μου» with the days left
 * behind (ADR-540), then the review and «Υπαναχώρηση» with its amount first.
 */
export function MyProgrammePage({ id }: { id: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const token = useSession().tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const today = useToday();
  const programmeError = useProgrammeError();
  const [withdrawing, setWithdrawing] = useState(false);
  const purchase = useQuery({
    queryKey: myProgrammeKey(slug ?? "", id),
    enabled: Boolean(token && slug),
    queryFn: () => fetchMyProgramme(token!, slug!, id),
  });

  const back = <BackLink href="/box">{t("backToBox")}</BackLink>;
  if (purchase.isLoading) return <Page>{back}<p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Page>;
  if (!purchase.data) return <Page>{back}<ErrorNotice>{purchase.error ? programmeError(purchase.error) : t("notFound")}</ErrorNotice></Page>;

  const data = purchase.data;
  const dated = typeof data.starts_on === "string" && typeof data.ends_on === "string";
  const progress = dated ? programmeProgress(data.starts_on, data.ends_on, today) : null;
  const state = typeof data.status === "string" && PURCHASE_STATES.has(data.status) ? t(`purchaseState.${data.status}`) : null;

  return (
    <Page>
      {back}
      <header>
        <h1 className="text-2xl font-extrabold lg:text-3xl" style={{ color: "var(--text)" }}>{data.title ?? t("title")}</h1>
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {[state, data.version_number ? t("versionShort", { number: data.version_number }) : null].filter(Boolean).join(" · ")}
        </p>
      </header>

      {DAY_PURCHASE_STATES.has(data.status) && slug ? (
        <PurchaseDays slug={slug} token={token!} purchaseId={id} />
      ) : progress ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("daysProgress", { done: progress.done, total: progress.total })}</p>
      ) : null}

      {data.starts_on <= today && (data.status === "active" || data.status === "completed") && slug ? (
        <ReviewCard purchase={data} slug={slug} token={token!} />
      ) : null}

      {data.status === "active" ? (
        <section className="rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("withdrawTitle")}</h2>
          {data.refund ? (
            <>
              <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }} data-testid="my-programme-refund">
                {t("youGetBack", { amount: programmeMoney(locale, data.refund.amount_cents, data.currency) })}
                <span className="block text-xs" style={{ color: "var(--muted)" }}>{t(`ruleNote.${data.refund.rule}`)}</span>
              </p>
              <button type="button" onClick={() => setWithdrawing(true)} className="mt-3 min-h-11 text-sm font-semibold" style={{ color: "var(--danger)" }} data-testid="my-programme-withdraw-open">
                {t("withdraw")}
              </button>
            </>
          ) : (
            <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t("nothingBack")}</p>
          )}
        </section>
      ) : null}

      {withdrawing && data.refund && slug ? <WithdrawDialog purchase={data} slug={slug} token={token!} onClose={() => setWithdrawing(false)} /> : null}
    </Page>
  );
}

function Page({ children }: { children: React.ReactNode }) {
  return <main className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 pb-10 pt-4 lg:max-w-6xl lg:px-6" data-testid="my-programme">{children}</main>;
}

const PURCHASE_STATES = new Set(["pending_payment", "waiting", "active", "completed", "withdrawn", "refunded", "cancelled"]);

/** The purchases that have days to show (ADR-540). */
const DAY_PURCHASE_STATES = new Set(["waiting", "active", "completed"]);

/** The days of a purchase with «Κάν' τη σήμερα» and «Παράλειψη»; both refresh the days and the box's day. */
function PurchaseDays({ slug, token, purchaseId }: { slug: string; token: string; purchaseId: string }) {
  const t = useTranslations("Programmes");
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const days = useQuery({
    queryKey: programmeDaysKey(slug, purchaseId),
    queryFn: () => fetchProgrammeDays(token, slug, purchaseId),
    staleTime: FRESHNESS.live,
  });
  const act = useMutation({
    mutationFn: ({ action, day }: { action: "today" | "skip"; day: number }) =>
      action === "today" ? doProgrammeDayToday(token, slug, purchaseId, day) : skipProgrammeDay(token, slug, purchaseId, day),
    onSuccess: async (data) => {
      queryClient.setQueryData(programmeDaysKey(slug, purchaseId), data);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: programmeDaysKey(slug, purchaseId) }),
        queryClient.invalidateQueries({ queryKey: myProgrammesKey(slug) }),
        queryClient.invalidateQueries({ queryKey: ["box", "assignments"] }),
      ]);
    },
  });
  const view = useMemo(() => readDays(days.data), [days.data]);

  if (days.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (days.isError) return <ErrorNotice>{programmeError(days.error)}</ErrorNotice>;
  return (
    <ProgrammeDayBoard
      view={view}
      pending={act.isPending}
      error={act.isError ? programmeError(act.error) : null}
      onAction={(action, day) => act.mutate({ action, day })}
    />
  );
}

function WithdrawDialog({ purchase, slug, token, onClose }: { purchase: ProgrammePurchase; slug: string; token: string; onClose: () => void }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const amount = programmeMoney(locale, purchase.refund?.amount_cents ?? 0, purchase.currency);
  const withdraw = useMutation({
    mutationFn: () => withdrawProgramme(token, slug, purchase.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: myProgrammesKey(slug) });
      onClose();
    },
  });
  return (
    <Dialog
      onClose={onClose}
      title={t("withdrawTitle")}
      size="sm"
      testId="my-programme-withdraw"
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>{t("cancel")}</button>
          <button
            type="button"
            disabled={withdraw.isPending}
            onClick={() => withdraw.mutate()}
            className="min-h-11 rounded-full px-5 text-sm font-semibold disabled:opacity-50"
            style={dangerButtonStyle}
            data-testid="my-programme-withdraw-confirm"
          >
            {t("withdrawConfirm", { amount })}
          </button>
        </>
      }
    >
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("withdrawBody")}</p>
      {withdraw.isError ? <ErrorNotice variant="field" className="mt-2">{programmeError(withdraw.error)}</ErrorNotice> : null}
    </Dialog>
  );
}

function ReviewCard({ purchase, slug, token }: { purchase: ProgrammePurchase; slug: string; token: string }) {
  const t = useTranslations("Programmes");
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const bodyId = useId();
  const [rating, setRating] = useState(purchase.review?.rating ?? 0);
  const [body, setBody] = useState(purchase.review?.body ?? "");
  const [sent, setSent] = useState(false);
  const save = useMutation({
    mutationFn: () => reviewProgramme(token, slug, purchase.id, { rating, body: body.trim() || null }),
    onSuccess: async () => {
      setSent(true);
      await queryClient.invalidateQueries({ queryKey: myProgrammeKey(slug, purchase.id) });
    },
  });
  return (
    <section className="rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="my-programme-review">
      <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{purchase.review ? t("yourReview") : t("reviewAsk")}</h2>
      <div className="mt-2 flex gap-1" role="radiogroup" aria-label={t("ratingLabel")}>
        {[1, 2, 3, 4, 5].map((value) => (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={rating === value}
            aria-label={t("stars", { count: value })}
            onClick={() => setRating(value)}
            className="flex h-11 w-11 items-center justify-center text-2xl"
            style={{ color: value <= rating ? "var(--warning)" : "var(--border-strong)" }}
          >
            ★
          </button>
        ))}
      </div>
      <label htmlFor={bodyId} className="mt-2 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("reviewText")}</label>
      <textarea
        id={bodyId}
        rows={3}
        maxLength={1000}
        value={body}
        onChange={(event) => setBody(event.target.value)}
        className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
      />
      <button
        type="button"
        disabled={rating === 0 || save.isPending}
        onClick={() => save.mutate()}
        className="mt-3 min-h-11 rounded-full px-5 text-sm font-semibold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="my-programme-review-send"
      >
        {purchase.review ? t("reviewUpdate") : t("reviewSend")}
      </button>
      {sent ? <p className="mt-2 text-xs" role="status" style={{ color: "var(--success)" }}>{t("reviewThanks")}</p> : null}
      {save.isError ? <ErrorNotice variant="field" className="mt-2">{programmeError(save.error)}</ErrorNotice> : null}
    </section>
  );
}
