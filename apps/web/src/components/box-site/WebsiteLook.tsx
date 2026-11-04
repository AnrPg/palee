"use client";

import { useId, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { SiteAppearance, SitePaletteKey, SiteSection, SiteTemplateKey } from "@/api/box-site";

import { APPEARANCES, PALETTE_KEYS, PALETTES, siteTokens, TEMPLATE_KEYS } from "./templates/palettes";
import { NEW_SECTIONS, SECTION_GROUPS } from "./templates/site-model";
import { quickSections, sectionWrite, type SiteDraftPatch, type SiteDraftState } from "./website-draft-model";
import { sectionOn } from "./website-settings-model";

/**
 * ADR-530: «Εμφάνιση» (template, colours, light or dark, motion), «Τι δείχνει
 * η ιστοσελίδα» (the section switches in their groups) and the SEO/GEO card.
 * The app keeps its own theme; only the swatches show the website's colours.
 */

export const cardClass = "flex flex-col gap-3 rounded-3xl p-5";
export const cardStyle: CSSProperties = { background: "var(--panel)", border: "1px solid var(--border)" };
const subheadStyle: CSSProperties = { color: "var(--muted)", letterSpacing: "0.08em" };

type Effective = SiteDraftState & { forms_enabled: boolean };

/** Arrow keys move the choice within a radiogroup (and Home/End to its ends); the focus follows. */
function radioKeys<T extends string>(event: KeyboardEvent<HTMLElement>, keys: readonly T[], value: T, onChange: (next: T) => void) {
  const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
  const forward = rtl ? "ArrowLeft" : "ArrowRight";
  const back = rtl ? "ArrowRight" : "ArrowLeft";
  const index = keys.indexOf(value);
  let next = index;
  if (event.key === forward || event.key === "ArrowDown") next = (index + 1) % keys.length;
  else if (event.key === back || event.key === "ArrowUp") next = (index - 1 + keys.length) % keys.length;
  else if (event.key === "Home") next = 0;
  else if (event.key === "End") next = keys.length - 1;
  else return;
  event.preventDefault();
  onChange(keys[next]!);
  event.currentTarget.querySelector<HTMLElement>(`[data-radio="${keys[next]}"]`)?.focus();
}

export function SwitchButton({ checked, onChange, label, describedBy, disabled, testId }: { checked: boolean; onChange: (next: boolean) => void; label: string; describedBy?: string; disabled?: boolean; testId?: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      aria-describedby={describedBy}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className="relative inline-flex h-7 w-[2.875rem] shrink-0 items-center rounded-full transition-colors disabled:opacity-60"
      style={{ background: checked ? "var(--spark)" : "var(--control-bg)", border: checked ? "1px solid transparent" : "1px solid var(--control-border)" }}
      data-testid={testId}
    >
      <span
        aria-hidden
        className="inline-block h-[1.375rem] w-[1.375rem] rounded-full transition-transform motion-reduce:transition-none"
        style={{ background: "var(--control-knob)", boxShadow: "var(--shadow-sm)", transform: checked ? "translateX(1.2rem)" : "translateX(0.125rem)" }}
      />
    </button>
  );
}

function SwitchRow({ label, hint, badge, checked, onChange, disabled, first, testId }: { label: string; hint: string; badge?: ReactNode; checked: boolean; onChange: (next: boolean) => void; disabled?: boolean; first?: boolean; testId?: string }) {
  const hintId = useId();
  return (
    <div className="flex min-h-12 items-center gap-3 py-2.5" style={{ borderTop: first ? undefined : "1px solid var(--border)" }} data-testid={testId}>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="flex flex-wrap items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {label}
          {badge}
        </span>
        <span id={hintId} className="text-xs" style={{ color: "var(--muted)" }}>{hint}</span>
      </span>
      <SwitchButton checked={checked} onChange={onChange} label={label} describedBy={hintId} disabled={disabled} />
    </div>
  );
}

function Subhead({ children, id }: { children: ReactNode; id?: string }) {
  return (
    <h3 id={id} className="mt-2 text-xs font-bold uppercase" style={subheadStyle}>
      {children}
    </h3>
  );
}

/** A small sketch of each template's first screen, in the app's own colours. */
function TemplateSketch({ template }: { template: SiteTemplateKey }) {
  const ink = "var(--text)";
  const accent = "var(--primary)";
  const block = (style: CSSProperties) => <i className="absolute block" style={style} />;
  return (
    <span aria-hidden className="relative block h-14 overflow-hidden rounded-lg" style={{ background: "var(--bg)" }}>
      {template === "arena" ? (
        <>
          {block({ inset: "6px 6px 22px", borderRadius: 4, background: ink })}
          {block({ left: 10, bottom: 28, width: "40%", height: 8, background: accent })}
          {block({ left: 6, right: 6, bottom: 6, height: 10, background: accent, transform: "rotate(-2deg)" })}
        </>
      ) : null}
      {template === "tiles" ? (
        <>
          {block({ left: 6, top: 6, width: "58%", height: 44, borderRadius: 6, background: ink })}
          {block({ right: 6, top: 6, width: "30%", height: 20, borderRadius: 6, background: accent })}
          {block({ right: 6, top: 30, width: "30%", height: 20, borderRadius: 6, background: "var(--border-strong)" })}
        </>
      ) : null}
      {template === "stories" ? (
        <>
          {[0, 1, 2, 3].map((i) => (
            <i key={i} className="absolute block rounded-full" style={{ top: 6, left: 8 + i * 22, width: 16, height: 16, boxShadow: `0 0 0 2px ${accent}` }} />
          ))}
          {block({ left: 6, right: 6, top: 28, bottom: 4, borderRadius: 8, background: ink })}
        </>
      ) : null}
      {template === "atelier" ? (
        <>
          {block({ left: "50%", top: 6, width: 34, height: 50, transform: "translateX(-50%)", borderRadius: "20px 20px 0 0", background: ink })}
          {block({ left: 10, top: 16, width: 22, height: 3, borderRadius: 2, background: ink })}
          {block({ left: 10, top: 24, width: 16, height: 3, borderRadius: 2, background: "var(--border-strong)" })}
          {block({ left: 10, top: 32, width: 19, height: 3, borderRadius: 2, background: "var(--border-strong)" })}
        </>
      ) : null}
    </span>
  );
}

export function LookCard({ look, onChange, disabled }: { look: Effective; onChange: (patch: SiteDraftPatch) => void; disabled?: boolean }) {
  const t = useTranslations("WebsiteLook");
  const locale = useLocale();
  const ids = { template: useId(), colors: useId(), appearance: useId(), calm: useId() };
  const dark = look.appearance === "dark";
  const { aa } = siteTokens(look.palette, dark, look.template);
  const ratio = new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(aa);
  const setTemplate = (template: SiteTemplateKey) => onChange({ template });
  const setPalette = (palette: SitePaletteKey) => onChange({ palette });
  const setAppearance = (appearance: SiteAppearance) => onChange({ appearance });

  return (
    <section className={cardClass} style={cardStyle} data-testid="website-look">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("lookTitle")}</h2>

      <Subhead id={ids.template}>{t("template")}</Subhead>
      <div
        role="radiogroup"
        aria-labelledby={ids.template}
        className="grid grid-cols-2 gap-2 sm:grid-cols-4"
        onKeyDown={(event) => radioKeys(event, TEMPLATE_KEYS, look.template, setTemplate)}
      >
        {TEMPLATE_KEYS.map((key) => {
          const checked = look.template === key;
          return (
            <button
              key={key}
              type="button"
              role="radio"
              aria-checked={checked}
              tabIndex={checked ? 0 : -1}
              disabled={disabled}
              onClick={() => setTemplate(key)}
              data-radio={key}
              data-testid={`website-template-${key}`}
              className="flex flex-col gap-1.5 rounded-2xl p-2.5 text-start"
              style={{ border: `1.5px solid ${checked ? "var(--primary)" : "var(--border)"}`, boxShadow: checked ? "0 0 0 1px var(--primary)" : undefined, color: "var(--text)" }}
            >
              <TemplateSketch template={key} />
              <b className="text-sm">{t(`templates.${key}.name`)}</b>
              <span className="text-xs leading-snug" style={{ color: "var(--muted)" }}>{t(`templates.${key}.hint`)}</span>
            </button>
          );
        })}
      </div>

      <Subhead id={ids.colors}>{t("colors")}</Subhead>
      <div role="radiogroup" aria-labelledby={ids.colors} className="flex flex-wrap gap-2" onKeyDown={(event) => radioKeys(event, PALETTE_KEYS, look.palette, setPalette)}>
        {PALETTE_KEYS.map((key) => {
          const checked = look.palette === key;
          const p = PALETTES[key];
          return (
            <button
              key={key}
              type="button"
              role="radio"
              aria-checked={checked}
              tabIndex={checked ? 0 : -1}
              disabled={disabled}
              onClick={() => setPalette(key)}
              data-radio={key}
              data-testid={`website-palette-${key}`}
              className="grid w-[4.25rem] justify-items-center gap-1 rounded-xl p-0.5 text-[0.6875rem]"
              style={{ color: "var(--text)" }}
            >
              <i
                aria-hidden
                className="block h-[2.125rem] w-[2.125rem] rounded-full"
                style={{
                  // The website's own colours: the one place the settings page shows them (ADR-530).
                  background: `linear-gradient(135deg, ${p.accent} 0 55%, ${p.accent2} 55% 78%, ${p.deep} 78%)`,
                  boxShadow: checked ? "0 0 0 2px var(--panel), 0 0 0 4px var(--primary)" : "0 0 0 1px var(--border)",
                }}
              />
              {t(`palettes.${key}`)}
            </button>
          );
        })}
      </div>
      <p className="text-xs" style={{ color: "var(--muted)" }} data-testid="website-contrast">
        {aa >= 4.5 ? t("contrastAa", { ratio }) : t("contrast", { ratio })} {t("contrastHint")}
      </p>

      <Subhead id={ids.appearance}>{t("appearanceTitle")}</Subhead>
      <div role="radiogroup" aria-labelledby={ids.appearance} aria-describedby={`${ids.appearance}-hint`} className="flex flex-wrap gap-1.5" onKeyDown={(event) => radioKeys(event, APPEARANCES, look.appearance, setAppearance)}>
        {APPEARANCES.map((key) => {
          const checked = look.appearance === key;
          return (
            <button
              key={key}
              type="button"
              role="radio"
              aria-checked={checked}
              tabIndex={checked ? 0 : -1}
              disabled={disabled}
              onClick={() => setAppearance(key)}
              data-radio={key}
              className="min-h-9 rounded-full px-3.5 text-sm"
              style={
                checked
                  ? { background: "var(--spark)", color: "var(--spark-contrast)", border: "1px solid transparent", fontWeight: 700 }
                  : { background: "transparent", color: "var(--text)", border: "1px solid var(--border)" }
              }
            >
              {t(`appearance.${key}`)}
            </button>
          );
        })}
      </div>
      <p id={`${ids.appearance}-hint`} className="text-xs" style={{ color: "var(--muted)" }}>{t("appearanceHint")}</p>

      <Subhead>{t("motionTitle")}</Subhead>
      <SwitchRow first label={t("calm")} hint={t("calmHint")} checked={look.calm_motion} onChange={(calm_motion) => onChange({ calm_motion })} disabled={disabled} testId="website-calm" />
    </section>
  );
}

export function SectionsCard({ state, onChange, disabled }: { state: Effective; onChange: (patch: SiteDraftPatch) => void; disabled?: boolean }) {
  const t = useTranslations("WebsiteLook");
  const sections = useTranslations("BoxSite.sections");
  const chip = "min-h-9 rounded-full px-3.5 text-sm font-semibold disabled:opacity-50";
  const chipStyle: CSSProperties = { border: "1px solid var(--border)", color: "var(--text)", background: "transparent" };
  return (
    <section className={cardClass} style={cardStyle} data-testid="website-sections">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("sectionsTitle")}</h2>
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("sectionsHint")}</p>
      <div className="flex flex-wrap gap-1.5">
        <button type="button" className={chip} style={chipStyle} disabled={disabled} onClick={() => onChange(quickSections(state, "all"))} data-testid="website-sections-all">
          {t("quickAll")}
        </button>
        <button type="button" className={chip} style={chipStyle} disabled={disabled} onClick={() => onChange(quickSections(state, "basic"))} data-testid="website-sections-basic">
          {t("quickBasic")}
        </button>
      </div>
      {SECTION_GROUPS.map((group) => (
        <div key={group.key} className="flex flex-col" role="group" aria-label={t(`groups.${group.key}`)}>
          <h3 className="mt-2 text-xs font-bold" style={subheadStyle}>{t(`groups.${group.key}`)}</h3>
          {group.sections.map((key: SiteSection, index) => (
            <SwitchRow
              key={key}
              first={index === 0}
              label={sections(key)}
              hint={t(`sectionHints.${key}`)}
              badge={
                NEW_SECTIONS.includes(key) ? (
                  <span className="rounded-md px-1.5 text-[0.6875rem] font-extrabold uppercase" style={{ background: "var(--spark)", color: "var(--spark-contrast)", letterSpacing: "0.06em" }}>
                    {t("new")}
                  </span>
                ) : null
              }
              checked={sectionOn(state, key)}
              onChange={(on) => onChange(sectionWrite(state, key, on))}
              disabled={disabled}
              testId={`website-section-${key}`}
            />
          ))}
        </div>
      ))}
    </section>
  );
}

/** «Βρίσκεσαι στο Google και στις απαντήσεις AI» (ADR-530 §5): what Palee does on its own. */
export function SeoCard({ hasDomain }: { hasDomain: boolean }) {
  const t = useTranslations("WebsiteLook");
  const items = ["google", "data", "ai", "speed", "reviews"] as const;
  return (
    <section className={cardClass} style={cardStyle} data-testid="website-seo">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("seoTitle")}</h2>
      <div className="flex flex-col gap-2.5 rounded-2xl p-3.5" style={{ border: "1px solid var(--border)", background: "color-mix(in srgb, var(--success) 7%, var(--panel))" }}>
        <p className="text-sm" style={{ color: "var(--text)" }}>{t("seoIntro")}</p>
        <ul className="flex flex-col gap-2">
          {items.map((key) => (
            <li key={key} className="grid grid-cols-[1.125rem_1fr] gap-2 text-sm" style={{ color: "var(--text)" }}>
              <span aria-hidden className="font-extrabold" style={{ color: "var(--success)" }}>✓</span>
              <span>
                <b>{t(`seo.${key}.label`)}</b> {t(`seo.${key}.text`)}
              </span>
            </li>
          ))}
        </ul>
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {t.rich("seoTip", {
            domain: (chunks) =>
              hasDomain ? (
                chunks
              ) : (
                <a href="#website-domains" className="font-semibold underline" style={{ color: "var(--primary-strong)" }} data-testid="website-seo-domain">
                  {chunks}
                </a>
              ),
          })}
        </p>
      </div>
    </section>
  );
}

/** «Η ιστοσελίδα σου πήρε νέα όψη» for sites the migration moved to «Αρένα». */
export function NoticeBanner({ template, onClose, closing }: { template: SiteTemplateKey; onClose: () => void; closing?: boolean }) {
  const t = useTranslations("WebsiteLook");
  return (
    <div role="status" className="flex items-start gap-3 rounded-2xl px-4 py-3" style={{ background: "color-mix(in srgb, var(--spark) 22%, var(--panel))", border: "1px solid var(--border)" }} data-testid="website-notice">
      <p className="flex-1 text-sm" style={{ color: "var(--text)" }}>{t("notice", { template: t(`templates.${template}.name`) })}</p>
      <button type="button" onClick={onClose} disabled={closing} aria-label={t("noticeClose")} className="grid h-9 w-9 shrink-0 place-items-center rounded-full" style={{ color: "var(--text-soft)" }} data-testid="website-notice-close">
        ✕
      </button>
    </div>
  );
}
