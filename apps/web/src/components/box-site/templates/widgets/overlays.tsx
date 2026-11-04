"use client";

import Link from "next/link";
import { useId, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";

import { useSiteRequestForm } from "@/components/box-site/SiteRequestSheet";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { fieldErrorId } from "@/lib/public-site";

import { hoursSummary, mainLocation } from "../site-data";
import { CtaButton, PageLink, Photo, useSite, useSiteText } from "../site-context";

/**
 * A layer over the page (ADR-530): focus moves in, Tab stays inside, Esc
 * closes and focus goes back to what opened it; the page behind is inert
 * and does not scroll.
 */
export function OverlayShell({
  label,
  labelledBy,
  className = "",
  children,
  onKeyDown,
  style,
  testId,
}: {
  label?: string;
  labelledBy?: string;
  className?: string;
  children: ReactNode;
  onKeyDown?: (event: KeyboardEvent<HTMLDivElement>) => void;
  style?: CSSProperties;
  testId?: string;
}) {
  const { close } = useSite();
  const ref = useModalFocusTrap<HTMLDivElement>(close);
  return (
    <div className="bw-layer full">
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={labelledBy ? undefined : label}
        aria-labelledby={labelledBy}
        tabIndex={-1}
        className={`ovl ${className}`}
        onKeyDown={onKeyDown}
        style={style}
        data-testid={testId}
      >
        {children}
      </div>
    </div>
  );
}

function CloseButton({ className = "x", label }: { className?: string; label?: string }) {
  const { close } = useSite();
  const { t } = useSiteText();
  return (
    <button type="button" className={className} onClick={close} aria-label={label ?? t("close")} data-dialog-close>
      ✕
    </button>
  );
}

const WEEKDAYS = [1, 2, 3, 4, 5, 6];

/**
 * «Δωρεάν δοκιμαστικό τμήμα» / «Στείλε μας μήνυμα»: the request form in the
 * template's colours. A request never books a seat: it becomes a lead
 * (ADR-353). In the settings' preview it checks the fields and sends nothing.
 */
export function FormSheet({ kind, choice }: { kind: "trial" | "contact"; choice: string }) {
  const { site, page, preview, close, rootBase, language, locale } = useSite();
  const { t, tb } = useSiteText();
  const ids = useId();
  const titleId = `${ids}-title`;
  const [days, setDays] = useState<number[]>([]);
  const dayName = (weekday: number) => new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(new Date(Date.UTC(2024, 0, weekday)));
  const preferred = [choice, days.map(dayName).join(", ")].filter(Boolean).join(" · ");
  const request = useSiteRequestForm({ slug: site.slug, kind, preferred, preview });
  const { form, set, errors } = request;
  const privacyHref = `${rootBase}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`;
  const field = (name: "name" | "contact" | "message" | "privacy_ack") => ({
    "aria-invalid": errors[name] ? true : undefined,
    "aria-describedby": errors[name] ? fieldErrorId(ids, name) : undefined,
  });

  const body = request.sent ? (
    <>
      <h2 id={titleId}>{t("form.thanks", { name: form.name.trim() })}</h2>
      <p className="muted" style={{ margin: "6px 0 14px" }}>
        {kind === "trial" ? tb("form.trial.sentText") : t("form.contactSent")}
      </p>
      {preview ? <p className="note" style={{ marginBottom: 14 }}>{t("form.previewNote")}</p> : null}
      <button type="button" className="btn" onClick={close} data-testid="site-form-done">
        {t("form.ok")}
      </button>
    </>
  ) : (
    <>
      <h2 id={titleId}>{kind === "trial" ? t("form.trialTitle") : t("form.contactTitle")}</h2>
      <p className="muted">{kind === "trial" ? tb("form.trial.subtitle") : t("form.contactSub", { box: page.box.name })}</p>
      <form
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          void request.submit();
        }}
      >
        {choice ? <span className="chip" style={{ width: "max-content", maxWidth: "100%" }}>{t("form.choice", { choice })}</span> : null}
        {request.failed ? <p className="notice" role="alert">{tb("form.failed")}</p> : null}
        <div className="field">
          <label htmlFor={`${ids}-name`}>{tb("form.name")}</label>
          <input id={`${ids}-name`} value={form.name} onChange={(event) => set("name", event.target.value)} autoComplete="name" maxLength={80} {...field("name")} />
          {errors.name ? <p className="err" id={fieldErrorId(ids, "name")}>{tb("form.errors.nameRequired")}</p> : null}
        </div>
        <div className="field">
          <label htmlFor={`${ids}-contact`}>{tb("form.contact")}</label>
          <input id={`${ids}-contact`} value={form.contact} onChange={(event) => set("contact", event.target.value)} autoComplete="email" maxLength={160} {...field("contact")} />
          {errors.contact ? (
            <p className="err" id={fieldErrorId(ids, "contact")}>
              {tb(errors.contact === "invalid" ? "form.errors.contactInvalid" : "form.errors.contactRequired")}
            </p>
          ) : null}
        </div>
        {kind === "trial" ? (
          <div className="field">
            <span id={`${ids}-days`} style={{ fontSize: 13, fontWeight: 600 }}>
              {t("form.days")}
            </span>
            <div className="daychips" role="group" aria-labelledby={`${ids}-days`}>
              {WEEKDAYS.map((weekday) => (
                <button
                  key={weekday}
                  type="button"
                  aria-pressed={days.includes(weekday)}
                  onClick={() => setDays((current) => (current.includes(weekday) ? current.filter((value) => value !== weekday) : [...current, weekday].sort()))}
                >
                  {dayName(weekday)}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="field">
            <label htmlFor={`${ids}-message`}>{tb("form.message")}</label>
            <textarea id={`${ids}-message`} rows={3} value={form.message} onChange={(event) => set("message", event.target.value)} maxLength={2000} {...field("message")} />
            {errors.message ? <p className="err" id={fieldErrorId(ids, "message")}>{tb("form.errors.messageRequired")}</p> : null}
          </div>
        )}
        {/* Honeypot: people never see it; a bot that fills it is dropped (ADR-353). */}
        <input type="text" name="website" tabIndex={-1} autoComplete="off" aria-hidden="true" value={form.website} onChange={(event) => set("website", event.target.value)} className="honey" />
        <label className="consent">
          <input type="checkbox" checked={form.marketing} onChange={(event) => set("marketing", event.target.checked)} />
          <span>{tb("form.marketing")}</span>
        </label>
        <div>
          <label className="consent">
            <input type="checkbox" checked={form.privacy} onChange={(event) => set("privacy", event.target.checked)} {...field("privacy_ack")} />
            <span>
              {tb.rich("form.privacy", {
                link: (chunks) => (
                  <Link href={privacyHref} target="_blank" onClick={preview ? (event) => event.preventDefault() : undefined}>
                    {chunks}
                  </Link>
                ),
              })}
            </span>
          </label>
          {errors.privacy_ack ? <p className="err" id={fieldErrorId(ids, "privacy_ack")}>{tb("form.errors.privacyRequired")}</p> : null}
        </div>
        <button className="btn" type="submit" disabled={request.sending} data-testid="site-form-send">
          {request.sending ? tb("form.sending") : tb("form.trial.send")}
        </button>
      </form>
    </>
  );

  return (
    <OverlayShell labelledBy={titleId} testId={request.sent ? "site-form-sent" : "site-form"}>
      <div className="scrim" aria-hidden="true" onClick={request.sending ? undefined : close} />
      <div className="sheet">
        <div className="grab" aria-hidden="true" />
        <CloseButton />
        {body}
      </div>
    </OverlayShell>
  );
}

/** The photos full screen: arrows, swipe, ← → keys, a counter. */
export function Lightbox({ start }: { start: number }) {
  const { gallery } = useSite();
  const { t } = useSiteText();
  const [index, setIndex] = useState(start);
  const swipe = useRef<number | null>(null);
  const count = gallery.length;
  if (count === 0) return null;
  const current = ((index % count) + count) % count;
  const photo = gallery[current]!;
  const show = (next: number) => setIndex(next);
  return (
    <OverlayShell
      label={t("gallery.title")}
      onKeyDown={(event) => {
        if (event.key === "ArrowRight") show(current + 1);
        if (event.key === "ArrowLeft") show(current - 1);
      }}
      testId="site-lightbox"
    >
      <div
        className="light"
        onPointerDown={(event) => (swipe.current = event.clientX)}
        onPointerUp={(event) => {
          if (swipe.current !== null && Math.abs(event.clientX - swipe.current) > 50) show(current + (event.clientX < swipe.current ? 1 : -1));
          swipe.current = null;
        }}
      >
        <CloseButton />
        {count > 1 ? (
          <button type="button" className="x prev" onClick={() => show(current - 1)} aria-label={t("gallery.prev")}>
            ←
          </button>
        ) : null}
        <div className="shot">
          <Photo url={photo.url} alt={photo.caption ?? ""} icon={null} priority style={{ height: "100%", background: "none" }} />
        </div>
        {count > 1 ? (
          <button type="button" className="x next" onClick={() => show(current + 1)} aria-label={t("gallery.next")}>
            →
          </button>
        ) : null}
        <p className="cnt" aria-live="polite">
          {t("gallery.count", { index: current + 1, count })}
          {photo.caption ? ` · ${photo.caption}` : ""}
        </p>
      </div>
    </OverlayShell>
  );
}

/**
 * The full-screen menu: «Αρένα» in big condensed capitals on the deep colour,
 * «Ατελιέ» as a numbered list on paper. Links come in one after another.
 */
export function MenuOverlay() {
  const { pages, template, page, spans, locale, close } = useSite();
  const { t } = useSiteText();
  const location = mainLocation(page);
  const address = location ? [location.address, location.city].filter(Boolean).join(", ") : "";
  const hours = hoursSummary(spans, locale);
  const label = (key: string) => t(`pages.${key}`);
  if (template === "arena")
    return (
      <OverlayShell label={t("menu")} testId="site-menu">
        <div className="menuA">
          <CloseButton className="burger" label={t("closeMenu")} />
          <nav aria-label={t("pagesNav")}>
            {pages.map((entry, index) => (
              <PageLink key={entry.key} page={entry.key} style={{ animationDelay: `${index * 55}ms` }} onNavigate={close}>
                {label(entry.label)}
              </PageLink>
            ))}
          </nav>
          <div style={{ marginTop: 24 }}>
            <CtaButton />
          </div>
          {address ? <p className="meta">{address}</p> : null}
        </div>
      </OverlayShell>
    );
  return (
    <OverlayShell label={t("menu")} testId="site-menu">
      <div className="menuD">
        <button type="button" className="menuBtn" onClick={close} data-dialog-close>
          {t("closeMenu")} ✕
        </button>
        <nav aria-label={t("pagesNav")}>
          {pages.map((entry, index) => (
            <PageLink key={entry.key} page={entry.key} style={{ animationDelay: `${index * 70}ms` }} onNavigate={close}>
              <span className="n">{String(index + 1).padStart(2, "0")}</span>
              {label(entry.label)}
            </PageLink>
          ))}
        </nav>
        <div className="foot2">
          {address || hours ? (
            <p className="muted">
              {address}
              {address && hours ? <br /> : null}
              {hours}
            </p>
          ) : null}
          <CtaButton className="btnD" long dot />
        </div>
      </div>
    </OverlayShell>
  );
}
