"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useId, useState, useSyncExternalStore, type ReactNode } from "react";

import { termsLanguage } from "@/api/my-payments";
import { buyProgramme, fetchProgrammeTerms, fetchPublicProgramme, type ProgrammeTerms, type PublicProgramme } from "@/api/programmes";
import { Icon } from "@/components/box-page/Icon";
import { useStartCheckout } from "@/components/payments/PayParts";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationMemberships } from "@/lib/organization-slug";
import { nativePlatform } from "@/lib/platform";
import { canBuyHere } from "@/lib/platform/store-policy";
import { FRESHNESS } from "@/lib/query-policy";
import { newIdempotencyKey } from "@/lib/training-log";

import { needsStartRequest } from "./programme-grid";
import { coverUrl, previewDays, programmeFacts, refundPolicy, weekOutline, type OutlineWeek, type RefundPolicy } from "./programme-page-model";
import { programmeMoney, ratingStars, useProgrammeError, useProgrammeLabels } from "./programme-ui";
import { ProgrammeCover } from "./ProgrammeTile";

const noSubscription = () => () => {};
const sellableHere = () => canBuyHere({ kind: "programme" }, nativePlatform());

type Review = NonNullable<PublicProgramme["latest_reviews"]>[number];

/**
 * A programme's page (board 2κ/2μ A). Phone: one page that scrolls — cover
 * and title with the rating, the facts, «Δες δωρεάν τις N πρώτες μέρες»,
 * the reviews before the plan, the weeks as accordions (free days by name,
 * locked WODs counted), the FAQ — with a sticky bar of price, refund rule
 * and «Αγορά». Desktop: the same in a column with a sticky buy card beside
 * it. The store apps show no buy button and no price call to action (ADR-256).
 */
export function PublicProgrammePage({ slug, id }: { slug: string; id: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const labels = useProgrammeLabels();
  const [buying, setBuying] = useState(false);
  const [openWeeks, setOpenWeeks] = useState<Record<number, boolean>>({ 1: true });
  const weeksId = useId();
  // ADR-256: no buy button inside the store apps; the server render shows none either.
  const sellable = useSyncExternalStore(noSubscription, sellableHere, () => false);

  const page = useQuery({ queryKey: ["public", "programme", slug, id], queryFn: () => fetchPublicProgramme(slug, id), staleTime: FRESHNESS.reference });

  if (page.isLoading) return <Main><p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Main>;
  const programme = page.data?.programme;
  if (!programme || typeof programme !== "object" || typeof programme.title !== "string") {
    return <Main><ErrorNotice>{t("notFound")}</ErrorNotice></Main>;
  }

  const box = page.data?.box;
  const boxName = typeof box?.name === "string" ? box.name : slug;
  const facts = programmeFacts(programme);
  const outline = weekOutline(programme);
  const freeDays = previewDays(programme).length;
  const policy = refundPolicy(programme);
  const reviewCount = typeof programme.reviews?.count === "number" ? programme.reviews.count : 0;
  const stars = ratingStars(locale, programme.reviews?.average, reviewCount);
  const reviews = (Array.isArray(programme.latest_reviews) ? programme.latest_reviews : [])
    .filter((review): review is Review => Boolean(review && typeof review.id === "string" && review.status !== "hidden"))
    .slice(0, 2);
  const price = programmeMoney(locale, typeof programme.price_cents === "number" ? programme.price_cents : 0, programme.currency);
  const kind = [labels.goal(programme.goal), labels.level(programme.level)].filter(Boolean).join(" · ");

  const showPreview = () => {
    setOpenWeeks((current) => ({ ...current, 1: true }));
    document.getElementById(weeksId)?.scrollIntoView({ behavior: "smooth", block: "start" });
  };
  const previewButton = (className: string) =>
    freeDays > 0 ? (
      <button
        type="button"
        onClick={showPreview}
        className={`min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-bold ${className}`}
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        {t("buyer2.previewFree", { count: freeDays })}
      </button>
    ) : null;

  return (
    <Main>
      <BackLink href={`/b/${encodeURIComponent(slug)}`} className="min-h-11 self-start text-sm font-semibold">{boxName}</BackLink>

      <div className="lg:grid lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start lg:gap-10">
        <div className="flex min-w-0 flex-col gap-5">
          <header className="flex flex-col overflow-hidden rounded-3xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <ProgrammeCover programme={programme} className="flex aspect-video max-h-72 w-full flex-col justify-end gap-2 p-5 lg:p-7">
              {kind ? <span className="self-start rounded-full px-2.5 py-1 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--deep-contrast) 18%, transparent)" }}>{kind}</span> : null}
            </ProgrammeCover>
            <div className="flex flex-col gap-1 p-5 lg:px-7">
              {kind && coverUrl(programme) ? <p className="text-xs font-bold uppercase tracking-[0.12em]" style={{ color: "var(--dim)" }}>{kind}</p> : null}
              <h1 className="break-words text-2xl font-extrabold lg:text-3xl" style={{ color: "var(--text)" }}>{programme.title}</h1>
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>
                {[boxName, stars ? `${stars} · ${t("buyer2.reviewsCount", { count: reviewCount })}` : t("newBadge")].join(" · ")}
              </p>
            </div>
          </header>

          <Facts facts={facts} />

          {programme.summary ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{programme.summary}</p> : null}
          {programme.description ? <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{programme.description}</p> : null}

          {previewButton(sellable ? "flex lg:hidden" : "flex")}

          {reviews.length > 0 ? (
            <section className="flex flex-col gap-2" data-testid="programme-reviews">
              <h2 className="text-base font-bold lg:text-lg" style={{ color: "var(--text)" }}>{t("buyer2.reviews")}</h2>
              <div className="grid gap-3 lg:grid-cols-2">
                {reviews.map((review) => (
                  <blockquote key={review.id} className="flex flex-col gap-1 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                    <span className="flex items-center gap-2">
                      <b className="min-w-0 flex-1 truncate text-sm" style={{ color: "var(--text)" }}>{review.author?.nickname ?? ""}</b>
                      <span className="text-sm" style={{ color: "var(--warning)" }} aria-label={t("stars", { count: review.rating })}>{"★".repeat(Math.max(0, Math.min(5, review.rating || 0)))}</span>
                    </span>
                    {review.body ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{review.body}</p> : null}
                  </blockquote>
                ))}
              </div>
            </section>
          ) : null}

          {outline.length > 0 ? (
            <section id={weeksId} className="flex scroll-mt-20 flex-col gap-2" data-testid="programme-weeks">
              <h2 className="text-base font-bold lg:text-lg" style={{ color: "var(--text)" }}>{t("buyer2.weeksTitle")}</h2>
              {outline.map((week) => (
                <WeekAccordion
                  key={week.from}
                  week={week}
                  minutes={facts.minutes}
                  open={Boolean(openWeeks[week.from])}
                  onToggle={(open) => setOpenWeeks((current) => (current[week.from] === open ? current : { ...current, [week.from]: open }))}
                />
              ))}
            </section>
          ) : null}

          <Faq policy={policy} />
        </div>

        {sellable ? (
          <aside className="sticky top-24 hidden flex-col gap-3 rounded-3xl p-5 lg:flex" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="programme-buy-card">
            <span className="text-3xl font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{price}</span>
            {policy ? <span className="text-sm" style={{ color: "var(--muted)" }}>{t(`buyer2.refundShort.${policy}`)}</span> : null}
            <BuyButton onClick={() => setBuying(true)} testId="programme-buy-open-desktop" />
            {previewButton("flex")}
            <ul className="flex flex-col gap-1.5 pt-3 text-sm" style={{ borderTop: "1px solid var(--border)", color: "var(--text-soft)" }}>
              {(["perkStart", "perkDaily", "perkLog"] as const).map((perk) => (
                <li key={perk} className="flex items-center gap-2">
                  <span style={{ color: "var(--success)" }}><Icon name="check" size={16} /></span>
                  {t(`buyer2.${perk}`)}
                </li>
              ))}
            </ul>
          </aside>
        ) : null}
      </div>

      {sellable ? (
        <div
          className="sticky bottom-[calc(var(--bottom-float-inset)+0.5rem)] z-(--z-sticky) flex items-center gap-3 rounded-3xl p-3 shadow-lg lg:hidden"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
          data-testid="programme-buy-bar"
        >
          <span className="flex min-w-0 flex-col">
            <b className="text-lg font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{price}</b>
            {policy ? <span className="truncate text-xs" style={{ color: "var(--muted)" }}>{t(`buyer2.refundShort.${policy}`)}</span> : null}
          </span>
          <BuyButton onClick={() => setBuying(true)} testId="programme-buy-open" className="flex-1" />
        </div>
      ) : null}

      {buying ? <BuySheet slug={slug} boxName={boxName} programme={programme} onClose={() => setBuying(false)} /> : null}
    </Main>
  );
}

function Main({ children }: { children: ReactNode }) {
  return <main className="mx-auto flex w-full max-w-6xl flex-col gap-3 px-4 pb-10 pt-3 lg:px-6 lg:pt-6" data-testid="programme-page">{children}</main>;
}

function BuyButton({ onClick, testId, className = "" }: { onClick: () => void; testId: string; className?: string }) {
  const t = useTranslations("Programmes");
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex min-h-12 items-center justify-center rounded-2xl px-5 text-sm font-bold ${className}`}
      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      data-testid={testId}
    >
      {t("buyer2.buy")}
    </button>
  );
}

/** «6 εβδομάδες · 4 προπονήσεις την εβδομάδα · 45′ · Μπάρα»: the minutes and the equipment only when known (ADR-542). */
function Facts({ facts }: { facts: ReturnType<typeof programmeFacts> }) {
  const t = useTranslations("Programmes");
  const tEquipment = useTranslations("Equipment");
  const items: { key: string; value: string; label: string }[] = [];
  if (facts.weeks) items.push({ key: "weeks", value: String(facts.weeks), label: t("buyer2.factWeeks", { count: facts.weeks }) });
  if (facts.perWeek) items.push({ key: "perWeek", value: String(facts.perWeek), label: t("buyer2.factPerWeek", { count: facts.perWeek }) });
  if (facts.minutes) items.push({ key: "minutes", value: t("buyer2.minutes", { minutes: facts.minutes }), label: t("buyer2.factMinutes") });
  if (facts.equipment.length > 0) {
    items.push({ key: "equipment", value: facts.equipment.map((key) => tEquipment(key)).join(", "), label: t("buyer2.factEquipment") });
  }
  if (items.length === 0) return null;
  return (
    <dl className="grid grid-cols-2 gap-2 lg:grid-cols-4" data-testid="programme-facts">
      {items.map((item) => (
        <div key={item.key} className="flex min-w-0 flex-col-reverse gap-0.5 rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={`programme-fact-${item.key}`}>
          <dt className="text-xs" style={{ color: "var(--muted)" }}>{item.label}</dt>
          <dd className="break-words text-lg font-extrabold" style={{ color: "var(--text)" }}>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

/** One week (or the remaining weeks together): free days by name, locked WODs counted with their length. */
function WeekAccordion({ week, minutes, open, onToggle }: { week: OutlineWeek; minutes: number | null; open: boolean; onToggle: (open: boolean) => void }) {
  const t = useTranslations("Programmes");
  return (
    <details
      open={open}
      onToggle={(event) => onToggle((event.currentTarget as HTMLDetailsElement).open)}
      className="rounded-2xl"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid={`programme-week-${week.from}`}
    >
      <summary className="flex min-h-12 cursor-pointer items-center gap-2 px-4 text-sm font-bold" style={{ color: "var(--text)" }}>
        <span className="flex-1">{week.from === week.to ? t("buyer2.week", { week: week.from }) : t("buyer2.weekRange", { from: week.from, to: week.to })}</span>
        {week.open.length > 0 ? (
          <span className="rounded-full px-2 py-0.5 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
            {t("buyer2.freeCount", { count: week.open.length })}
          </span>
        ) : null}
      </summary>
      <ul className="flex flex-col px-4 pb-3">
        {week.open.map((day) => (
          <li key={day.day} className="flex min-h-11 items-center gap-3 py-1.5 text-sm" style={{ borderTop: "1px solid var(--border)" }}>
            <span className="w-12 shrink-0 text-xs font-bold" style={{ color: "var(--dim)" }}>{t("dayShort", { day: day.dayOfWeek })}</span>
            <b className="min-w-0 flex-1 break-words" style={{ color: "var(--text)" }}>{day.titles.join(" · ") || t("unknownWod")}</b>
            <span className="shrink-0 text-xs font-bold" style={{ color: "var(--success)" }}>{t("buyer2.free")}</span>
          </li>
        ))}
        {week.locked > 0 ? (
          <li className="flex min-h-11 items-center gap-3 py-1.5 text-sm" style={{ borderTop: "1px solid var(--border)", color: "var(--muted)" }}>
            <span className="w-12 shrink-0" aria-hidden="true"><Icon name="lock" size={16} /></span>
            <span className="min-w-0 flex-1">
              {t("buyer2.locked", { count: week.locked })}
              {minutes ? ` · ${t("buyer2.lockedEach", { minutes })}` : ""}
            </span>
            <span className="shrink-0 text-xs">{t("buyer2.lockedHint")}</span>
          </li>
        ) : null}
        {week.open.length === 0 && week.locked === 0 ? (
          <li className="py-2 text-sm" style={{ borderTop: "1px solid var(--border)", color: "var(--dim)" }}>{t("rest")}</li>
        ) : null}
      </ul>
    </details>
  );
}

function Faq({ policy }: { policy: RefundPolicy | null }) {
  const t = useTranslations("Programmes");
  const entries: { key: string; question: string; answer: string }[] = [
    { key: "start", question: t("buyer2.faqStartQ"), answer: t("buyer2.faqStartA") },
    { key: "miss", question: t("buyer2.faqMissQ"), answer: t("buyer2.faqMissA") },
    ...(policy ? [{ key: "refund", question: t("buyer2.faqRefundQ"), answer: t(`buyer2.faqRefund.${policy}`) }] : []),
  ];
  return (
    <section className="flex flex-col gap-2" data-testid="programme-faq">
      <h2 className="text-base font-bold lg:text-lg" style={{ color: "var(--text)" }}>{t("buyer2.faqTitle")}</h2>
      {entries.map((entry) => (
        <details key={entry.key} className="rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <summary className="flex min-h-12 cursor-pointer items-center px-4 text-sm font-bold" style={{ color: "var(--text)" }}>{entry.question}</summary>
          <p className="px-4 pb-3 text-sm" style={{ color: "var(--text-soft)" }}>{entry.answer}</p>
        </details>
      ))}
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
