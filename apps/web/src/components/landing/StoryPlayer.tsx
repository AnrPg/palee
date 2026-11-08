"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import { BRAND_NAME } from "@/components/branding/brand";
import { PaleeMark } from "@/components/branding/PaleeMark";
import { PaleeTagline } from "@/components/branding/PaleeTagline";
import {
  AutoVisual,
  BoxVisual,
  JournalVisual,
  PartnerVisual,
  PostVisual,
  ProgressVisual,
} from "@/components/landing/LandingVisuals";
import { BUSINESS_LANDING_HREF } from "@/components/business-landing/links";
import { StoryFrame } from "@/components/landing/StoryFrame";

export const LANDING_PHOTO = "/landing-gym-floor.jpg";

const STORIES = ["hero", "crew", "journal", "progress", "partners", "box", "auto", "business"] as const;
type Story = (typeof STORIES)[number];

const em = { em: (chunks: ReactNode) => <em>{chunks}</em> };

function StorySlide({ story }: { story: Story }) {
  const t = useTranslations("Landing");
  if (story === "hero") {
    return (
      <div className="grid gap-4">
        <PaleeTagline className="landing-rise text-base" accent="var(--spark)" />
        <h1 className="landing-rise landing-rise-1 landing-em text-4xl font-black leading-[1.05] tracking-tight">
          {t.rich("hero.title", em)}
        </h1>
        <p className="landing-rise landing-rise-2 landing-soft text-base">{t("hero.lede")}</p>
        <div className="landing-rise landing-rise-2 overflow-hidden rounded-2xl">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={LANDING_PHOTO} alt={t("photoAlt")} className="landing-kenburns aspect-[3/2] w-full object-cover" />
        </div>
      </div>
    );
  }
  if (story === "business") {
    return (
      <div className="grid gap-4">
        <h2 className="landing-rise landing-em text-3xl font-black leading-[1.08] tracking-tight">{t("owner.title")}</h2>
        <p className="landing-rise landing-rise-1 landing-soft text-base">{t("owner.body")}</p>
        <Link
          href={BUSINESS_LANDING_HREF}
          className="landing-rise landing-rise-2 landing-pulse inline-flex min-h-12 items-center justify-center justify-self-start rounded-full px-6 font-extrabold"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          onPointerDown={(event) => event.stopPropagation()}
          onPointerUp={(event) => event.stopPropagation()}
        >
          {t("forBusiness")} →
        </Link>
      </div>
    );
  }
  const visual = {
    crew: <PostVisual />,
    journal: <JournalVisual />,
    progress: <ProgressVisual />,
    partners: <PartnerVisual />,
    box: <BoxVisual />,
    auto: <AutoVisual />,
  }[story];
  return (
    <div className="grid gap-4">
      <h2 className="landing-rise landing-em text-3xl font-black leading-[1.08] tracking-tight">
        {t.rich(`story.${story}Title`, em)}
      </h2>
      <p className="landing-rise landing-rise-1 landing-soft text-base">{t(`story.${story}Body`)}</p>
      <div className="landing-rise landing-rise-2">{visual}</div>
    </div>
  );
}

/**
 * Phones (ADR-555): Palee told in full-screen stories, like the ones people
 * already know. The last story points box owners and coaches to the business
 * landing (ADR-556). The player itself is the shared `StoryFrame`.
 */
export function StoryPlayer({
  onSignUp,
  onSignIn,
  suspended = false,
}: {
  onSignUp: () => void;
  onSignIn: () => void;
  /** True while the sign-in sheet covers the stories: they wait for it. */
  suspended?: boolean;
}) {
  const t = useTranslations("Landing");
  return (
    <StoryFrame
      count={STORIES.length}
      renderSlide={(index) => <StorySlide story={STORIES[index]} />}
      suspended={suspended}
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
        <span className="flex items-center gap-2 text-lg font-black">
          <PaleeMark className="size-7 [&_path]:stroke-[var(--deep-contrast)]" />
          {BRAND_NAME}
        </span>
      }
      actions={
        <>
          <button
            type="button"
            onClick={onSignUp}
            className="min-h-12 rounded-full px-5 text-base font-extrabold"
            style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          >
            {t("getStarted")}
          </button>
          <button
            type="button"
            onClick={onSignIn}
            className="min-h-12 rounded-full px-5 text-base font-bold"
            style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 40%, transparent)" }}
          >
            {t("haveAccount")}
          </button>
        </>
      }
    />
  );
}
