"use client";

import Link from "next/link";
import { useCallback, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { AuthPanel, type AuthMode } from "@/components/auth-console";
import { PaleeMark } from "@/components/branding/PaleeMark";
import { PaleeTagline } from "@/components/branding/PaleeTagline";
import { BUSINESS_LANDING_HREF } from "@/components/business-landing/links";
import { Dialog } from "@/components/ui/Dialog";
import {
  AutoVisual,
  BoxVisual,
  JournalVisual,
  PartnerVisual,
  PostVisual,
  ProgressVisual,
  ClubVisual,
} from "@/components/landing/LandingVisuals";
import { PhoneDemo } from "@/components/landing/PhoneDemo";
import { useReveal } from "@/components/landing/use-reveal";
import { LANDING_PHOTO, StoryPlayer } from "@/components/landing/StoryPlayer";

const em = { em: (chunks: ReactNode) => <em>{chunks}</em> };
const noSubscription = () => () => {};

/** Sign in or sign up over the landing: a bottom sheet on phones, a blue end drawer from tablets up. */
function AuthDrawer({ mode, onClose, onContinue }: { mode: AuthMode; onClose: () => void; onContinue?: () => void }) {
  const t = useTranslations("Landing");
  const common = useTranslations("Common");
  return (
    <Dialog
      onClose={onClose}
      ariaLabel={t("authDialog")}
      variant="panel"
      size="lg"
      bare
      panelClassName="landing-auth-drawer overflow-y-auto"
      testId="landing-auth-drawer"
    >
      <div className="relative flex min-h-full flex-col px-4 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-14 md:px-8 md:py-14">
        <button
          type="button"
          onClick={onClose}
          aria-label={common("close")}
          className="absolute end-3 top-3 grid size-11 place-items-center rounded-full text-xl font-bold"
          style={{ background: "var(--panel)", color: "var(--text)" }}
        >
          ×
        </button>
        <div
          className="mx-auto my-auto w-full max-w-md md:rounded-[2rem] md:border md:border-(--border) md:p-7 md:shadow-(--shadow-lg)"
          style={{ background: "var(--panel)", color: "var(--text)" }}
        >
          <AuthPanel key={mode} initialMode={mode} onContinue={onContinue} />
        </div>
      </div>
    </Dialog>
  );
}

function SparkButton({ onClick, children, className = "" }: { onClick: () => void; children: ReactNode; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`min-h-11 rounded-full px-5 text-sm font-extrabold ${className}`}
      style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
    >
      {children}
    </button>
  );
}

const PILLAR_ICON = { crew: "🤝", journal: "📓", partners: "🏋️", auto: "⚡" } as const;

function Pillar({ id, index }: { id: keyof typeof PILLAR_ICON; index: number }) {
  const t = useTranslations("Landing");
  return (
    <article
      className="landing-reveal landing-lift flex flex-col gap-1.5 rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", ["--reveal-delay" as string]: `${index * 0.1}s` }}
    >
      <span className="landing-bob grid size-11 place-items-center rounded-2xl text-2xl" style={{ background: "var(--panel-muted)", animationDelay: `${index * -1.4}s` }} aria-hidden="true">
        {PILLAR_ICON[id]}
      </span>
      <p className="mt-2 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>{t(`pillars.${id}Kicker`)}</p>
      <h3 className="text-xl font-black tracking-tight">{t(`pillars.${id}Title`)}</h3>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`pillars.${id}Body`)}</p>
    </article>
  );
}

/** A tile of «Why you'll open it every day»: what it is on top, the picture filling the rest. */
function Tile({ title, body, children, wide = false, full = false, index }: { title: string; body?: string; children?: ReactNode; wide?: boolean; full?: boolean; index: number }) {
  return (
    <article
      className={`landing-reveal landing-lift flex min-w-0 flex-col gap-4 rounded-3xl p-5 lg:p-6 ${wide ? "lg:col-span-2" : ""} ${full ? "md:col-span-2" : ""}`}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", ["--reveal-delay" as string]: `${(index % 3) * 0.12}s` }}
    >
      <header className="grid gap-1.5">
        <h3 className="text-lg font-black leading-snug tracking-tight lg:text-xl">{title}</h3>
        {body ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{body}</p> : null}
      </header>
      <div className="flex flex-1 flex-col [&>*]:flex-1">{children}</div>
    </article>
  );
}

/** Small notes popping in and out around the hero phone. */
function HeroChip({ children, className, start }: { children: ReactNode; className: string; start: number }) {
  return (
    <span
      className={`landing-chip absolute whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-extrabold shadow-lg ${className}`}
      style={{ background: "var(--panel)", color: "var(--text)", animationDelay: `${start}s` }}
      aria-hidden="true"
    >
      {children}
    </span>
  );
}

/**
 * The page people see on palee.app before they sign in (ADR-555). Phones get
 * stories; tablets and up open on one dark screen with the animated phone and
 * a Spark «See more» that scrolls to the rest. Sign in and sign up open over
 * it, and the page behind is inert meanwhile.
 *
 * `initialMode` opens the form straight away (/login, /register keep working
 * as links). `onAuthDone` is called when the form is done and the app takes
 * over; without it the form goes to `next` itself.
 */
export function GuestLanding({
  initialMode = null,
  onAuthOpen,
  onAuthDone,
}: {
  initialMode?: AuthMode | null;
  onAuthOpen?: () => void;
  onAuthDone?: () => void;
}) {
  const t = useTranslations("Landing");
  const [mode, setMode] = useState<AuthMode | null>(initialMode);
  // The form is a portal, which the server cannot render: /login and
  // /register show it right after hydration.
  const hydrated = useSyncExternalStore(
    noSubscription,
    () => true,
    () => false,
  );
  const rest = useRef<HTMLDivElement>(null);
  useReveal(rest);
  const words = t("marquee").split(" · ");

  const open = useCallback(
    (next: AuthMode) => {
      onAuthOpen?.();
      setMode(next);
    },
    [onAuthOpen],
  );

  const formOpen = hydrated && mode !== null;
  const signUp = () => open("register");
  const signIn = () => open("login");

  return (
    <>
      <div inert={formOpen} aria-hidden={formOpen ? true : undefined} data-testid="guest-landing">
        <div className="sm:hidden">
          <StoryPlayer onSignUp={signUp} onSignIn={signIn} suspended={formOpen} />
        </div>

        <div className="hidden sm:block" style={{ background: "var(--bg)", color: "var(--text)" }}>
          <header className="landing-deep sticky top-0 z-(--z-sticky) flex h-16 items-center justify-between gap-4 px-6 lg:px-16" style={{ backgroundImage: "none" }}>
            <span className="flex items-center gap-4">
              <span className="flex items-center gap-2 text-xl font-black">
                <PaleeMark className="size-8 [&_path]:stroke-[var(--deep-contrast)]" />
                Palee
              </span>
              {/* ADR-556: the way to the business landing sits with the brand, away from sign in / sign up. */}
              <Link
                href={BUSINESS_LANDING_HREF}
                className="landing-soft inline-flex min-h-11 items-center gap-1 border-s ps-4 text-sm font-semibold underline-offset-4 hover:underline"
                style={{ borderColor: "color-mix(in srgb, var(--deep-contrast) 25%, transparent)" }}
                data-testid="landing-for-business"
              >
                {t("forBusiness")} →
              </Link>
            </span>
            <div className="flex flex-wrap items-center justify-end gap-2">
              <button
                type="button"
                onClick={signIn}
                className="min-h-11 rounded-full px-4 text-sm font-bold"
                style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 35%, transparent)" }}
              >
                {t("signIn")}
              </button>
              <SparkButton onClick={signUp}>{t("getStarted")}</SparkButton>
            </div>
          </header>

          <section className="landing-deep landing-glow relative grid min-h-[calc(100dvh-4rem)] grid-cols-[minmax(0,1fr)_auto] items-center gap-8 overflow-hidden px-6 pb-24 pt-6 lg:gap-14 lg:px-16 2xl:px-[max(5rem,calc((100%-87.5rem)/2))]">
            <div className="grid max-w-2xl gap-5">
              <PaleeTagline className="landing-rise text-base lg:text-lg" accent="var(--spark)" />
              <h1 className="landing-rise landing-rise-1 landing-em text-5xl font-black leading-[1.02] tracking-tight lg:text-6xl 2xl:text-7xl">
                {t.rich("hero.title", em)}
              </h1>
              <p className="landing-rise landing-rise-2 landing-soft max-w-xl text-lg 2xl:text-xl">{t("hero.lede")}</p>
              <div className="landing-rise landing-rise-3 flex flex-wrap gap-3">
                <SparkButton onClick={signUp} className="min-h-12 px-6 text-base">{t("getStarted")}</SparkButton>
              </div>
            </div>
            <div className="landing-rise landing-rise-2 relative">
              <div className="landing-bob">
                <PhoneDemo />
              </div>
              <HeroChip className="-start-16 top-10" start={0}>🔥 {t("demo.post1Kudos")}</HeroChip>
              <HeroChip className="-end-6 top-1/2" start={2.5}>🏆 {t("tiles.badge")}</HeroChip>
              <HeroChip className="-start-10 bottom-16" start={5}>✓ {t("tiles.booked")} · {t("tiles.today")}</HeroChip>
            </div>
            <button
              type="button"
              onClick={() => rest.current?.scrollIntoView({ behavior: "smooth", block: "start" })}
              className="landing-cue absolute bottom-6 left-1/2 inline-flex min-h-11 items-center gap-2 rounded-full px-5 text-sm font-extrabold"
              style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
            >
              {t("seeMore")}
              <svg viewBox="0 0 24 24" className="size-4" aria-hidden="true">
                <path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" strokeWidth="2.8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          </section>

          <div ref={rest} className="scroll-mt-16" data-testid="landing-rest">
            <section className="mx-auto grid max-w-6xl gap-4 px-6 py-12 md:grid-cols-2 lg:grid-cols-4 lg:px-10">
              {(["crew", "journal", "partners", "auto"] as const).map((id, index) => (
                <Pillar key={id} id={id} index={index} />
              ))}
            </section>

            <div className="landing-marquee py-4" aria-hidden="true">
              <div className="landing-marquee-track flex w-max gap-[1.6rem] whitespace-nowrap text-lg font-extrabold" style={{ color: "var(--text-soft)" }}>
                {[0, 1].flatMap((copy) =>
                  words.map((word) => (
                    <span key={`${copy}-${word}`} className="landing-marquee-word">
                      {word}
                    </span>
                  )),
                )}
              </div>
            </div>

            <section className="mx-auto max-w-6xl px-6 py-14 lg:px-10">
              <h2 className="landing-reveal text-3xl font-black tracking-tight lg:text-4xl">{t("whyTitle")}</h2>
              <div className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <Tile index={0} title={t("tiles.shareTitle")} body={t("tiles.shareBody")} wide>
                  <PostVisual />
                </Tile>
                <Tile index={1} title={t("tiles.journalTitle")} body={t("tiles.journalBody")} wide>
                  <JournalVisual week />
                </Tile>
                <Tile index={2} title={t("tiles.partnersTitle")} body={t("tiles.partnersBody")}>
                  <PartnerVisual />
                </Tile>
                <Tile index={3} title={t("tiles.clubTitle")} body={t("tiles.clubBody")}>
                  <ClubVisual photo={LANDING_PHOTO} />
                </Tile>
                <Tile index={4} title={t("tiles.autoTitle")} wide>
                  <AutoVisual />
                </Tile>
                <Tile index={5} title={t("tiles.progressTitle")} body={t("tiles.progressBody")} wide>
                  <ProgressVisual />
                </Tile>
                <Tile index={6} title={t("tiles.boxTitle")} body={t("tiles.boxBody")} wide full>
                  <BoxVisual />
                </Tile>
              </div>
            </section>

            <section className="mx-auto max-w-6xl px-6 pb-16 lg:px-10">
              <div className="landing-deep landing-glow landing-reveal grid gap-4 rounded-[2rem] p-8 md:grid-cols-[1fr_auto] md:items-center lg:p-10">
                <div>
                  <h2 className="text-2xl font-black tracking-tight lg:text-3xl">{t("owner.title")}</h2>
                  <p className="landing-soft mt-2 max-w-2xl">{t("owner.body")}</p>
                </div>
                <Link
                  href={BUSINESS_LANDING_HREF}
                  className="landing-lift inline-flex min-h-12 items-center justify-center rounded-full px-6 font-extrabold"
                  style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
                >
                  {t("owner.cta")} →
                </Link>
              </div>
            </section>
          </div>
        </div>
      </div>

      {formOpen && mode ? <AuthDrawer mode={mode} onClose={() => setMode(null)} onContinue={onAuthDone} /> : null}
    </>
  );
}
