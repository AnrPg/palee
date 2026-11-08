"use client";

import Link from "next/link";
import { useCallback, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

import { PaleeMark } from "@/components/branding/PaleeMark";
import { BUSINESS_SIGN_UP_HREF } from "@/components/business/BusinessSignUp";
import { BusinessConsole } from "@/components/business-landing/BusinessConsole";
import { BusinessVisual, splitList } from "@/components/business-landing/BusinessVisuals";
import { COMPARISON, FEATURES, MANAGEMENT, STORIES, type Audience, type TileSpec } from "@/components/business-landing/content";
import { HowItWorks } from "@/components/business-landing/HowItWorks";
import { StoryFrame } from "@/components/landing/StoryFrame";
import { useReveal } from "@/components/landing/use-reveal";

const em = { em: (chunks: ReactNode) => <em>{chunks}</em> };
const spark = { background: "var(--spark)", color: "var(--spark-contrast)" } as const;

function Arrow() {
  return (
    <svg viewBox="0 0 24 24" className="size-4" aria-hidden="true">
      <path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" strokeWidth="2.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** «For: Box / Independent coach», quiet on purpose: most visitors never touch it. */
function AudienceSwitch({ audience, onChange, compact = false }: { audience: Audience; onChange: (next: Audience) => void; compact?: boolean }) {
  const t = useTranslations("BusinessLanding");
  return (
    <div
      role="group"
      aria-label={t("audience.label")}
      className="inline-flex items-center gap-1 justify-self-start rounded-full p-1 text-sm"
      style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 22%, transparent)" }}
      data-testid="business-audience"
    >
      {compact ? null : <span className="ps-2 pe-0.5 landing-soft">{t("audience.label")}:</span>}
      {(["box", "coach"] as const).map((option) => (
        <button
          key={option}
          type="button"
          aria-pressed={audience === option}
          onClick={() => onChange(option)}
          className="min-h-9 rounded-full px-3 font-bold transition-colors"
          style={
            audience === option
              ? { background: "color-mix(in srgb, var(--deep-contrast) 16%, transparent)", color: "var(--deep-contrast)" }
              : { color: "color-mix(in srgb, var(--deep-contrast) 65%, transparent)" }
          }
        >
          {option === "coach" && compact ? t("audience.coachShort") : t(`audience.${option}`)}
        </button>
      ))}
    </div>
  );
}

/** The hero's word that changes every three seconds. */
function RotatingWord({ words }: { words: string[] }) {
  return (
    <b className="landing-words" style={{ color: "var(--spark)" }}>
      {words.map((word, index) => (
        <span key={word} style={{ animationDelay: `${index * 3}s` }} aria-hidden={index > 0 ? true : undefined}>
          {word}
        </span>
      ))}
    </b>
  );
}

function Tile({ tile, index }: { tile: TileSpec; index: number }) {
  const t = useTranslations("BusinessLanding");
  const span = tile.full ? "md:col-span-2 lg:col-span-4" : tile.wide ? "md:col-span-2" : "";
  const surface = tile.dark
    ? { background: "var(--deep)", color: "var(--deep-contrast)", border: "1px solid transparent" }
    : { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" };
  return (
    <article
      className={`landing-reveal landing-lift flex min-w-0 flex-col gap-4 overflow-hidden rounded-[1.75rem] p-5 lg:p-6 ${span}`}
      style={{ ...surface, ["--reveal-delay" as string]: `${(index % 4) * 0.08}s` }}
      data-testid={`business-tile-${tile.id}`}
    >
      <header className="grid gap-1.5">
        <p className="flex items-center gap-2 text-xs font-extrabold uppercase tracking-[0.16em]" style={{ color: tile.dark ? "var(--spark)" : "var(--primary)" }}>
          {t(`tiles.${tile.id}.kicker`)}
          {tile.soon ? (
            <span className="rounded-full px-2 py-0.5 text-[10px] tracking-[0.08em]" style={{ background: "var(--heat)", color: "var(--heat-contrast)" }}>
              {t("management.soon")}
            </span>
          ) : null}
        </p>
        <h3 className="text-xl font-black leading-snug tracking-tight">{t(`tiles.${tile.id}.title`)}</h3>
        <p className="text-sm" style={{ color: tile.dark ? "color-mix(in srgb, var(--deep-contrast) 75%, transparent)" : "var(--text-soft)" }}>
          {t(`tiles.${tile.id}.body`)}
        </p>
      </header>
      <div className="mt-auto grid min-h-28 place-items-center">
        <BusinessVisual id={tile.visual} />
      </div>
    </article>
  );
}

/** One column on phones, two on tablets, four from laptops up; dense, so no holes (see `gridHoles`). */
function Bento({ tiles }: { tiles: TileSpec[] }) {
  return (
    <div className="landing-swap grid grid-flow-row-dense gap-4 md:grid-cols-2 lg:grid-cols-4">
      {tiles.map((tile, index) => (
        <Tile key={tile.id} tile={tile} index={index} />
      ))}
    </div>
  );
}

function SectionHead({ kicker, title, lede }: { kicker: string; title: string; lede?: string }) {
  return (
    <div className="landing-reveal mb-7 grid max-w-3xl gap-2">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>{kicker}</p>
      <h2 className="text-3xl font-black leading-[1.05] tracking-tight lg:text-4xl">{title}</h2>
      {lede ? <p style={{ color: "var(--text-soft)" }}>{lede}</p> : null}
    </div>
  );
}

/**
 * palee.app/business (ADR-556): the page that sells Palee to boxes and
 * independent coaches. The same language as the guest landing (ADR-555):
 * stories on phones; from tablets up a dark first screen with a live
 * console, then the free website and e-shop, the features, the running of
 * the business, how to start and what each one gets. A quiet switch shows
 * the coach's side (`?for=coach`); «See how it works» opens the day.
 */
export function BusinessLanding({ initialAudience }: { initialAudience: Audience }) {
  const t = useTranslations("BusinessLanding");
  const router = useRouter();
  const [audience, setAudience] = useState<Audience>(initialAudience);
  const [howOpen, setHowOpen] = useState(false);
  const rest = useRef<HTMLDivElement>(null);
  useReveal(rest, audience);

  const choose = useCallback((next: Audience) => {
    setAudience(next);
    const url = new URL(window.location.href);
    if (next === "coach") url.searchParams.set("for", "coach");
    else url.searchParams.delete("for");
    window.history.replaceState(window.history.state, "", url);
  }, []);
  const start = useCallback(() => router.push(BUSINESS_SIGN_UP_HREF), [router]);

  const words = splitList(t(`hero.${audience}.words`));
  const shopPoints = splitList(t(audience === "coach" ? "shop.coachPoints" : "shop.points"));

  return (
    <>
      <div inert={howOpen} aria-hidden={howOpen ? true : undefined} data-testid="business-landing">
        <div className="sm:hidden">
          <StoryFrame
            count={STORIES[audience].length}
            resetKey={audience}
            suspended={howOpen}
            renderSlide={(index) => {
              const story = STORIES[audience][index];
              const Heading = index === 0 ? "h1" : "h2";
              return (
                <div className="grid gap-4">
                  <p className="landing-rise text-xs font-extrabold uppercase tracking-[0.2em]" style={{ color: "var(--spark)" }}>
                    {t(`stories.${audience}.${story.id}.kicker`)}
                  </p>
                  <Heading className="landing-rise landing-rise-1 landing-em text-3xl font-black leading-[1.08] tracking-tight">
                    {t.rich(`stories.${audience}.${story.id}.title`, em)}
                  </Heading>
                  <p className="landing-rise landing-rise-1 landing-soft text-base">{t(`stories.${audience}.${story.id}.body`)}</p>
                  <div className="landing-rise landing-rise-2 grid min-h-48 place-items-center">
                    <BusinessVisual id={story.visual} />
                  </div>
                </div>
              );
            }}
            labels={{
              carousel: t("stories.label"),
              pause: t("stories.pause"),
              play: t("stories.play"),
              paused: t("stories.paused"),
              previous: t("stories.previous"),
              next: t("stories.next"),
              position: (current, total) => t("stories.position", { current, total }),
            }}
            brand={
              <span className="flex min-w-0 items-center gap-2">
                <PaleeMark className="size-7 shrink-0 [&_path]:stroke-[var(--deep-contrast)]" />
                <AudienceSwitch audience={audience} onChange={choose} compact />
              </span>
            }
            actions={
              <>
                <Link href={BUSINESS_SIGN_UP_HREF} className="grid min-h-12 place-items-center rounded-full px-5 text-base font-extrabold" style={spark}>
                  {t("hero.cta")}
                </Link>
                <div className="flex flex-wrap items-center justify-between gap-2 text-sm font-bold">
                  <Link href="/login" className="inline-flex min-h-11 items-center">{t("nav.signIn")}</Link>
                  <button type="button" onClick={() => setHowOpen(true)} className="inline-flex min-h-11 items-center gap-1.5" style={{ color: "var(--spark)" }}>
                    ▶ {t("hero.how")}
                  </button>
                  <Link href="/" className="inline-flex min-h-11 items-center">{t("nav.athletes")} →</Link>
                </div>
              </>
            }
          />
        </div>

        <div className="hidden sm:block" style={{ background: "var(--bg)", color: "var(--text)" }}>
          <header className="landing-deep sticky top-0 z-(--z-sticky) flex h-16 items-center justify-between gap-4 px-6 lg:px-16" style={{ backgroundImage: "none" }}>
            <Link href="/business" className="flex items-center gap-2 text-xl font-black">
              <PaleeMark className="size-8 [&_path]:stroke-[var(--deep-contrast)]" />
              Palee
              <span className="rounded-full px-2.5 py-0.5 text-[11px] font-extrabold uppercase tracking-[0.12em]" style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 35%, transparent)" }}>
                {t("brandTag")}
              </span>
            </Link>
            <nav className="flex flex-wrap items-center justify-end gap-2">
              <Link href="/" className="hidden min-h-11 items-center rounded-full px-3 text-sm font-bold hover:underline md:inline-flex">{t("nav.athletes")}</Link>
              <Link href="/login" className="inline-flex min-h-11 items-center rounded-full px-4 text-sm font-bold" style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 35%, transparent)" }}>
                {t("nav.signIn")}
              </Link>
              <Link href={BUSINESS_SIGN_UP_HREF} className="inline-flex min-h-11 items-center rounded-full px-5 text-sm font-extrabold" style={spark}>
                {t("nav.start")}
              </Link>
            </nav>
          </header>

          <section className="landing-deep landing-glow relative grid min-h-[calc(100dvh-4rem)] items-center gap-10 overflow-hidden px-6 pb-28 pt-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,34rem)] lg:gap-14 lg:px-16 2xl:px-[max(5rem,calc((100%-87.5rem)/2))]">
            <div className="landing-grid pointer-events-none absolute inset-0" aria-hidden="true" />
            <div className="relative grid max-w-2xl gap-5">
              <AudienceSwitch audience={audience} onChange={choose} />
              <div key={audience} className="landing-swap grid gap-5">
                <p className="text-xs font-extrabold uppercase tracking-[0.2em]" style={{ color: "var(--spark)" }}>{t(`hero.${audience}.eyebrow`)}</p>
                <h1 className="landing-em text-5xl font-black leading-[1.02] tracking-tight lg:text-6xl 2xl:text-7xl">{t.rich(`hero.${audience}.title`, em)}</h1>
                <p className="landing-soft max-w-xl text-lg 2xl:text-xl">
                  {t.rich(`hero.${audience}.lede`, { word: () => <RotatingWord words={words} /> })}
                </p>
              </div>
              <div className="flex flex-wrap gap-3">
                <Link href={BUSINESS_SIGN_UP_HREF} className="inline-flex min-h-12 items-center rounded-full px-6 text-base font-extrabold" style={spark}>
                  {t("hero.cta")}
                </Link>
                <button
                  type="button"
                  onClick={() => setHowOpen(true)}
                  className="inline-flex min-h-12 items-center gap-2 rounded-full px-6 text-base font-bold"
                  style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 35%, transparent)" }}
                >
                  ▶ {t("hero.how")}
                </button>
              </div>
            </div>
            <div className="relative grid justify-items-center lg:justify-items-end">
              <BusinessConsole audience={audience} />
            </div>
            <button
              type="button"
              onClick={() => rest.current?.scrollIntoView({ behavior: "smooth", block: "start" })}
              className="landing-cue absolute bottom-6 left-1/2 inline-flex min-h-11 items-center gap-2 rounded-full px-5 text-sm font-extrabold"
              style={spark}
            >
              {t("hero.seeMore")}
              <Arrow />
            </button>
          </section>

          <div className="landing-marquee py-5" aria-hidden="true">
            <div className="landing-marquee-track flex w-max gap-[1.6rem] whitespace-nowrap text-xl font-black" style={{ color: "var(--text-soft)" }}>
              {[0, 1].flatMap((copy) =>
                splitList(t(`marquee.${audience}`)).map((word) => (
                  <span key={`${copy}-${word}`} className="landing-marquee-word">{word}</span>
                )),
              )}
            </div>
          </div>

          <div ref={rest} className="scroll-mt-16" data-testid="business-rest">
            <section className="mx-auto max-w-6xl px-6 pt-14 lg:px-10">
              <div className="landing-reveal landing-deep landing-glow grid gap-8 overflow-hidden rounded-[2.25rem] p-7 md:p-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:items-center" data-testid="business-shop">
                <div className="relative grid gap-4">
                  <span className="justify-self-start rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em]" style={spark}>{t("shop.kicker")}</span>
                  <h2 className="text-3xl font-black leading-[1.05] tracking-tight lg:text-5xl">{t(`shop.${audience}`)}</h2>
                  <p className="landing-soft text-lg">{t("shop.body")}</p>
                  <ul className="grid gap-2 sm:grid-cols-2">
                    {shopPoints.map((point) => (
                      <li key={point} className="flex items-start gap-2 text-sm font-semibold">
                        <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full text-[11px] font-black" style={spark} aria-hidden="true">✓</span>
                        {point}
                      </li>
                    ))}
                  </ul>
                  <Link href={BUSINESS_SIGN_UP_HREF} className="landing-lift mt-1 inline-flex min-h-12 items-center justify-self-start rounded-full px-6 font-extrabold" style={spark}>
                    {t("shop.cta")} →
                  </Link>
                </div>
                <div className="relative grid gap-4 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                  <BusinessVisual id="website" />
                  <BusinessVisual id="shop" />
                </div>
              </div>
            </section>

            <section className="mx-auto max-w-6xl px-6 py-14 lg:px-10">
              <SectionHead kicker={t("features.kicker")} title={t(`features.${audience}`)} />
              <Bento key={`features-${audience}`} tiles={FEATURES[audience]} />
            </section>

            <div style={{ background: "var(--panel-muted)" }}>
              <section className="mx-auto max-w-6xl px-6 py-14 lg:px-10">
                <SectionHead kicker={t("management.kicker")} title={t(`management.${audience}`)} lede={t("management.lede")} />
                <Bento key={`management-${audience}`} tiles={MANAGEMENT[audience]} />
              </section>
            </div>

            <section className="mx-auto max-w-6xl px-6 py-14 lg:px-10">
              <SectionHead kicker={t("steps.kicker")} title={t("steps.title")} />
              <ol className="grid gap-4 md:grid-cols-3">
                {(["one", "two", "three"] as const).map((step, index) => (
                  <li key={step} className="landing-reveal landing-lift grid content-start gap-2 rounded-[1.75rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)", ["--reveal-delay" as string]: `${index * 0.1}s` }}>
                    <span className="grid size-10 place-items-center rounded-full text-lg font-black" style={spark} aria-hidden="true">{index + 1}</span>
                    <h3 className="text-lg font-black">{t(`steps.${step}Title`)}</h3>
                    <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`steps.${step}Body`)}</p>
                  </li>
                ))}
              </ol>
            </section>

            <section className="mx-auto max-w-6xl px-6 pb-14 lg:px-10">
              <SectionHead kicker={t("compare.kicker")} title={t("compare.title")} />
              <div className="landing-reveal overflow-x-auto rounded-[1.75rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <table className="w-full min-w-[32rem] border-collapse text-sm" data-testid="business-compare">
                  <thead>
                    <tr>
                      <th scope="col" className="px-4 py-3 text-start font-bold">{t("compare.feature")}</th>
                      {(["box", "coach"] as const).map((column) => (
                        <th
                          key={column}
                          scope="col"
                          className="px-4 py-3 text-center font-extrabold"
                          style={column === audience ? spark : undefined}
                        >
                          {t(`audience.${column}`)}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {COMPARISON.map((row) => (
                      <tr key={row.id} style={{ borderTop: "1px solid var(--border)" }}>
                        <th scope="row" className="px-4 py-3 text-start font-medium">{t(`compare.rows.${row.id}`)}</th>
                        {(["box", "coach"] as const).map((column) => (
                          <td
                            key={column}
                            className="px-4 py-3 text-center font-black"
                            style={{
                              color: row[column] ? "var(--primary)" : "var(--muted)",
                              background: column === audience ? "color-mix(in srgb, var(--spark) 16%, transparent)" : undefined,
                            }}
                          >
                            <span aria-hidden="true">{row[column] ? "✓" : "—"}</span>
                            <span className="sr-only">{row[column] ? t("compare.yes") : t("compare.no")}</span>
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>

            <section className="mx-auto max-w-6xl px-6 pb-16 lg:px-10">
              <div className="landing-reveal landing-deep landing-glow grid gap-5 rounded-[2.25rem] p-8 md:grid-cols-[1fr_auto] md:items-center lg:p-11">
                <div className="grid gap-2">
                  <h2 className="text-3xl font-black tracking-tight lg:text-4xl">{t(`cta.${audience}`)}</h2>
                  <p className="landing-soft">{t("cta.body")}</p>
                </div>
                <Link href={BUSINESS_SIGN_UP_HREF} className="landing-lift landing-pulse inline-flex min-h-13 items-center justify-center rounded-full px-7 text-base font-extrabold" style={spark}>
                  {t("cta.button")} →
                </Link>
              </div>
            </section>

            <footer className="mx-auto flex max-w-6xl flex-wrap justify-between gap-4 px-6 pb-10 text-sm lg:px-10" style={{ color: "var(--muted)" }}>
              <span>Palee · palee.app</span>
              <span className="flex flex-wrap gap-4">
                <Link href="/" className="hover:underline">{t("footer.athletes")}</Link>
                <Link href="/terms" className="hover:underline">{t("footer.terms")}</Link>
                <Link href="/privacy" className="hover:underline">{t("footer.privacy")}</Link>
              </span>
            </footer>
          </div>
        </div>
      </div>

      {howOpen ? (
        <HowItWorks
          audience={audience}
          onClose={() => setHowOpen(false)}
          onStart={() => {
            setHowOpen(false);
            start();
          }}
        />
      ) : null}
    </>
  );
}
