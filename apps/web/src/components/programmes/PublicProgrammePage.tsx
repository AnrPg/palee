"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useId, useState, type ReactNode } from "react";

import { termsLanguage } from "@/api/my-payments";
import { buyProgramme, fetchProgrammeTerms, fetchPublicProgramme, type ProgrammeTerms, type PublicProgramme } from "@/api/programmes";
import { useStartCheckout } from "@/components/payments/PayParts";
import { useSession } from "@/components/session-provider";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationMemberships } from "@/lib/organization-slug";
import { nativePlatform } from "@/lib/platform";
import { canBuyHere } from "@/lib/platform/store-policy";
import { newIdempotencyKey } from "@/lib/training-log";

import { DAYS_PER_WEEK, needsStartRequest } from "./programme-grid";
import { programmeMoney, ratingLabel, useProgrammeError, useProgrammeLabels } from "./programme-ui";

/**
 * A programme's page (mockup W8 s4 A): one page that scrolls — what it is,
 * then the first week with the open preview days and the locked ones, then
 * reviews. «Αγορά» opens the buy sheet (s5 A) on the web; the store apps
 * show no buy button and no link to buy on the web (ADR-256).
 */
export function PublicProgrammePage({ slug, id }: { slug: string; id: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const labels = useProgrammeLabels();
  const [buying, setBuying] = useState(false);
  const [sellable, setSellable] = useState(false);
  useEffect(() => setSellable(canBuyHere({ kind: "programme" }, nativePlatform())), []);

  const page = useQuery({ queryKey: ["public", "programme", slug, id], queryFn: () => fetchPublicProgramme(slug, id) });

  if (page.isLoading) return <Main><p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Main>;
  if (!page.data) return <Main><ErrorNotice>{t("notFound")}</ErrorNotice></Main>;

  const { programme, box } = page.data;
  const rating = ratingLabel(locale, programme.reviews?.average, programme.reviews?.count);
  const boxName = typeof box?.name === "string" ? box.name : slug;
  const price = programmeMoney(locale, programme.price_cents, programme.currency);

  return (
    <Main>
      <header className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
          {[programme.weeks ? t("weeks", { count: programme.weeks }) : null, labels.level(programme.level), labels.goal(programme.goal)].filter(Boolean).join(" · ")}
        </p>
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{programme.title}</h1>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          <Link href={`/b/${encodeURIComponent(slug)}`} className="font-semibold" style={{ color: "var(--text)" }}>{boxName}</Link>
          {rating ? ` · ${rating}` : ""}
        </p>
      </header>

      {programme.summary ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{programme.summary}</p> : null}
      {programme.description ? <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{programme.description}</p> : null}

      <Preview programme={programme} />

      {(programme.latest_reviews ?? []).length > 0 ? (
        <section className="flex flex-col gap-2" aria-label={t("tab.reviews")}>
          <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("tab.reviews")}</h2>
          {(programme.latest_reviews ?? []).map((review) => (
            <blockquote key={review.id} className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              {review.body ? <p className="text-sm" style={{ color: "var(--text)" }}>«{review.body}»</p> : null}
              <p className="mt-1 text-xs" style={{ color: "var(--muted)" }} aria-label={t("stars", { count: review.rating })}>
                {review.author?.nickname ? `${review.author.nickname} · ` : ""}{"★".repeat(review.rating)}
              </p>
            </blockquote>
          ))}
        </section>
      ) : null}

      {sellable ? (
        <div className="sticky bottom-4 flex justify-center">
          <button
            type="button"
            onClick={() => setBuying(true)}
            className="flex min-h-12 w-full max-w-sm items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            data-testid="programme-buy-open"
          >
            {t("buyFor", { price })}
          </button>
        </div>
      ) : null}

      {buying ? <BuySheet slug={slug} boxName={boxName} programme={programme} onClose={() => setBuying(false)} /> : null}
    </Main>
  );
}

function Main({ children }: { children: ReactNode }) {
  return <main className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 pb-10 pt-6" data-testid="programme-page">{children}</main>;
}

/** Week 1: the preview days with their WOD titles, the rest locked (s4 A). */
function Preview({ programme }: { programme: PublicProgramme }) {
  const t = useTranslations("Programmes");
  const open = new Map((programme.preview ?? []).filter((day) => day.week === 1).map((day) => [day.day, day]));
  const firstWeek = (programme.week_outline ?? []).find((week) => week.week === 1)?.sessions ?? open.size;
  const locked = Math.max(0, firstWeek - open.size);
  if (open.size === 0 && locked === 0) return null;
  return (
    <section className="flex flex-col gap-2" data-testid="programme-preview-week">
      <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("previewWeek")}</h2>
      {[...open.values()].sort((a, b) => a.day - b.day).map((day) => (
        <article key={day.day} className="flex items-start gap-3 rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <span className="shrink-0 text-xs font-bold" style={{ color: "var(--dim)" }}>{t("dayLong", { day: (day.day % DAYS_PER_WEEK) + 1 })}</span>
          <span className="min-w-0">
            <b className="block text-sm" style={{ color: "var(--text)" }}>{day.title ?? t("unknownWod")}</b>
            {day.summary ? <span className="block text-xs" style={{ color: "var(--muted)" }}>{day.summary}</span> : null}
          </span>
          <span className="ms-auto shrink-0 text-xs font-semibold" style={{ color: "var(--success)" }}>{t("open")}</span>
        </article>
      ))}
      {locked > 0 ? (
        <p className="rounded-2xl p-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px dashed var(--border-strong)", color: "var(--muted)" }}>
          🔒 {t("lockedDays", { count: locked })}
        </p>
      ) : null}
    </section>
  );
}

/** «Αγορά προγράμματος» (s5 A): start date, the request to start only when needed, total, pay at the box's provider. */
function BuySheet({ slug, boxName, programme, onClose }: { slug: string; boxName: string; programme: PublicProgramme; onClose: () => void }) {
  const t = useTranslations("Programmes");
  const tPay = useTranslations("Pay");
  const { status } = useSession();
  const memberships = useOrganizationMemberships();
  const member = (memberships.data ?? []).some((membership) => membership.organization.slug === slug);
  const here = `/b/${encodeURIComponent(slug)}/programmes/${encodeURIComponent(programme.id)}`;

  return (
    <Dialog onClose={onClose} title={t("buyTitle")} eyebrow={programme.title} size="sm" variant="sheet" testId="programme-buy">
      {status === "guest" ? (
        <div className="flex flex-col gap-3">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{tPay("signInToBuy")}</p>
          <div className="flex gap-2">
            <SheetLink href={`/register?next=${encodeURIComponent(here)}`} primary>{tPay("signUp")}</SheetLink>
            <SheetLink href={`/login?next=${encodeURIComponent(here)}`}>{tPay("signIn")}</SheetLink>
          </div>
        </div>
      ) : status !== "authenticated" || memberships.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : !member ? (
        <div className="flex flex-col gap-3">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("joinFirst", { box: boxName })}</p>
          <SheetLink href={`/join/${encodeURIComponent(slug)}?next=${encodeURIComponent(here)}`} primary>{tPay("join")}</SheetLink>
        </div>
      ) : (
        <Checkout slug={slug} boxName={boxName} programme={programme} />
      )}
    </Dialog>
  );
}

function Checkout({ slug, boxName, programme }: { slug: string; boxName: string; programme: PublicProgramme }) {
  const t = useTranslations("Programmes");
  const locale = useUiLocale();
  const language = termsLanguage(locale);
  const token = useSession().tokens?.access_token ?? null;
  const start = useStartCheckout();
  const programmeError = useProgrammeError();
  const startId = useId();
  const consentId = useId();
  const [key] = useState(newIdempotencyKey);
  const [startsOn, setStartsOn] = useState<string>("");
  const [startNow, setStartNow] = useState(false);

  const terms = useQuery({
    queryKey: ["programmes", "terms", slug, programme.id, language],
    enabled: Boolean(token),
    queryFn: () => fetchProgrammeTerms(token!, slug, programme.id, language),
    staleTime: 60_000,
  });
  const data: ProgrammeTerms | undefined = terms.data;
  const chosen = startsOn || data?.earliest_start || "";
  const asks = data ? needsStartRequest(chosen, data.earliest_start, data.withdrawal_days) : false;
  const ready = Boolean(data?.available) && !data?.owned && Boolean(chosen) && (!asks || startNow);

  const pay = useMutation({
    mutationFn: async () => {
      const { payment } = await buyProgramme(token!, slug, programme.id, {
        idempotency_key: key,
        starts_on: chosen,
        language,
        ...(asks ? { start_now: true } : {}),
      });
      await start(payment, { slug, kind: "programme", itemName: programme.title, origin: "box", autopay: false });
    },
  });

  if (terms.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (terms.isError || !data) return <ErrorNotice>{programmeError(terms.error)}</ErrorNotice>;
  if (data.owned) return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("alreadyOwned")}</p>;

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div>
        <label htmlFor={startId} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("startsOn")}</label>
        <DateInput
          id={startId}
          value={chosen}
          min={data.earliest_start}
          max={data.latest_start}
          onValueChange={(value) => {
            setStartsOn(value);
            setStartNow(false);
          }}
          data-testid="programme-start-date"
        />
      </div>
      {asks ? (
        <label htmlFor={consentId} className="flex items-start gap-3 rounded-2xl p-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}>
          <input id={consentId} type="checkbox" checked={startNow} onChange={(event) => setStartNow(event.target.checked)} className="mt-1" data-testid="programme-start-now" />
          <span>{data.start_now_text}</span>
        </label>
      ) : null}
      <p className="text-xs" style={{ color: "var(--muted)" }}>{data.refund_text}</p>
      <div className="flex items-baseline justify-between gap-3 border-t pt-3" style={{ borderColor: "var(--border)" }}>
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("totalWithVat")}</span>
        <span className="text-lg font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{programmeMoney(locale, programme.price_cents, programme.currency)}</span>
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("receiptFromBox", { box: boxName, version: data.terms_version })}</p>
      {!data.available ? <ErrorNotice variant="field">{t("errors.online_payments_unavailable")}</ErrorNotice> : null}
      <button
        type="button"
        disabled={!ready || pay.isPending}
        onClick={() => pay.mutate()}
        className="flex min-h-12 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="programme-pay"
      >
        {t("payAt", { box: boxName })}
      </button>
      {pay.isError ? <ErrorNotice variant="field">{programmeError(pay.error)}</ErrorNotice> : null}
    </div>
  );
}

function SheetLink({ href, children, primary }: { href: string; children: ReactNode; primary?: boolean }) {
  return (
    <Link
      href={href}
      className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
      style={primary ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
    >
      {children}
    </Link>
  );
}
