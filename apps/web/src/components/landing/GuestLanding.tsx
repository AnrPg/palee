"use client";

import Link from "next/link";
import { useCallback, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { AuthPanel, type AuthMode } from "@/components/auth-console";
import { PaleeMark } from "@/components/branding/PaleeMark";
import { PaleeTagline } from "@/components/branding/PaleeTagline";
import { BUSINESS_SIGN_UP_HREF } from "@/components/business/BusinessSignUp";
import { Dialog } from "@/components/ui/Dialog";
import {
  AutoVisual,
  BoxVisual,
  JournalVisual,
  PartnerVisual,
  PostVisual,
  ProgressVisual,
} from "@/components/landing/LandingVisuals";
import { PhoneDemo } from "@/components/landing/PhoneDemo";
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

function Pillar({ id }: { id: "crew" | "journal" | "partners" | "auto" }) {
  const t = useTranslations("Landing");
  return (
    <article className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>{t(`pillars.${id}Kicker`)}</p>
      <h3 className="mt-2 text-xl font-black tracking-tight">{t(`pillars.${id}Title`)}</h3>
      <p className="mt-1.5 text-sm" style={{ color: "var(--text-soft)" }}>{t(`pillars.${id}Body`)}</p>
    </article>
  );
}

function Tile({ title, body, children, wide = false }: { title: string; body?: string; children?: ReactNode; wide?: boolean }) {
  return (
    <article
      className={`flex min-w-0 flex-col gap-3 rounded-3xl p-5 ${wide ? "lg:col-span-2" : ""}`}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <h3 className="text-lg font-black tracking-tight">{title}</h3>
      {children}
      {body ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{body}</p> : null}
    </article>
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
            <span className="flex items-center gap-2 text-xl font-black">
              <PaleeMark className="size-8 [&_path]:stroke-[var(--deep-contrast)]" />
              Palee
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

          <section className="landing-deep relative grid min-h-[calc(100dvh-4rem)] grid-cols-[minmax(0,1fr)_auto] items-center gap-8 overflow-hidden px-6 pb-24 pt-6 lg:gap-14 lg:px-16 2xl:px-[max(5rem,calc((100%-87.5rem)/2))]">
            <div className="grid max-w-2xl gap-5">
              <PaleeTagline className="landing-rise text-base lg:text-lg" accent="var(--spark)" />
              <h1 className="landing-rise landing-rise-1 landing-em text-5xl font-black leading-[1.02] tracking-tight lg:text-6xl 2xl:text-7xl">
                {t.rich("hero.title", em)}
              </h1>
              <p className="landing-rise landing-rise-2 landing-soft max-w-xl text-lg 2xl:text-xl">{t("hero.lede")}</p>
              <div className="landing-rise landing-rise-2 flex flex-wrap gap-3">
                <SparkButton onClick={signUp} className="min-h-12 px-6 text-base">{t("getStarted")}</SparkButton>
              </div>
            </div>
            <PhoneDemo photo={LANDING_PHOTO} />
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
              <Pillar id="crew" />
              <Pillar id="journal" />
              <Pillar id="partners" />
              <Pillar id="auto" />
            </section>

            <div className="overflow-hidden py-4" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} aria-hidden="true">
              <p className="landing-marquee flex w-max gap-8 whitespace-nowrap text-lg font-black">
                <span>{t("marquee")}</span>
                <span>{t("marquee")}</span>
              </p>
            </div>

            <section className="mx-auto max-w-6xl px-6 py-14 lg:px-10">
              <h2 className="text-3xl font-black tracking-tight lg:text-4xl">{t("whyTitle")}</h2>
              <div className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <Tile title={t("tiles.shareTitle")} body={t("tiles.shareBody")} wide>
                  <PostVisual photo={LANDING_PHOTO} />
                </Tile>
                <Tile title={t("tiles.journalTitle")} body={t("tiles.journalBody")} wide>
                  <JournalVisual />
                </Tile>
                <Tile title={t("tiles.partnersTitle")} body={t("tiles.partnersBody")}>
                  <PartnerVisual />
                </Tile>
                <Tile title={t("tiles.clubTitle")} body={t("tiles.clubBody")} />
                <Tile title={t("tiles.autoTitle")} wide>
                  <AutoVisual />
                </Tile>
                <Tile title={t("tiles.progressTitle")} body={t("tiles.progressBody")} wide>
                  <ProgressVisual />
                </Tile>
                <Tile title={t("tiles.boxTitle")} body={t("tiles.boxBody")}>
                  <BoxVisual />
                </Tile>
                <figure className="relative overflow-hidden rounded-3xl" style={{ border: "1px solid var(--border)" }}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={LANDING_PHOTO} alt={t("photoAlt")} className="h-full min-h-56 w-full object-cover" loading="lazy" />
                  <figcaption
                    className="absolute bottom-3 start-3 rounded-full px-3 py-1.5 text-sm font-bold"
                    style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}
                  >
                    {t("photoCaption")}
                  </figcaption>
                </figure>
              </div>
            </section>

            <section className="mx-auto max-w-6xl px-6 pb-16 lg:px-10">
              <div className="landing-deep grid gap-4 rounded-[2rem] p-8 md:grid-cols-[1fr_auto] md:items-center lg:p-10">
                <div>
                  <h2 className="text-2xl font-black tracking-tight lg:text-3xl">{t("owner.title")}</h2>
                  <p className="landing-soft mt-2 max-w-2xl">{t("owner.body")}</p>
                </div>
                <Link
                  href={BUSINESS_SIGN_UP_HREF}
                  className="inline-flex min-h-12 items-center justify-center rounded-full px-6 font-extrabold"
                  style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
                >
                  {t("owner.cta")}
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
