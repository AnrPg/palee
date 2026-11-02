"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { recordSiteConsent, type PublicSite } from "@/api/box-site";
import { Dialog } from "@/components/ui/Dialog";
import {
  allowedTags,
  CONSENT_DEFAULT,
  consentAction,
  consentCategories,
  consentCookie,
  consentModeUpdate,
  readConsent,
  type ConsentChoice,
  type SiteTags,
  type StoredConsent,
} from "@/lib/site-consent";

type Ctx = { open: () => void; visitorId: () => string | null; marketing: () => boolean };
const ConsentContext = createContext<Ctx>({ open: () => undefined, visitorId: () => null, marketing: () => false });

/** «Cookies» in the footer reopens the choice; forms read the visitor id (ADR-354 §5). */
export function useSiteConsent() {
  return useContext(ConsentContext);
}

const subscribeNever = () => () => undefined;
const readCookies = () => document.cookie;
const serverCookies = () => "";
const nowMs = () => Date.now();

/**
 * The cookie bar of a box's website (ANR s4 A): a bar at the bottom with
 * three equal buttons, «Απόρριψη όλων», «Ρυθμίσεις», «Αποδοχή όλων».
 * Nothing loads before a choice; there is no bar when the box has no tags.
 */
export function SiteConsentProvider({ slug, site, children }: { slug: string; site: PublicSite; children: ReactNode }) {
  const t = useTranslations("BoxSite");
  const tracking = site.tracking;
  const needed = tracking.consent_required;
  const hydrated = useSyncExternalStore(subscribeNever, () => true, () => false);
  const cookies = useSyncExternalStore(subscribeNever, readCookies, serverCookies);
  const [stored, setStored] = useState<StoredConsent | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const fromCookie = useMemo(
    () => (needed && cookies ? readConsent(cookies, slug, tracking.banner_version, nowMs()) : null),
    [cookies, needed, slug, tracking.banner_version],
  );
  const current = stored ?? fromCookie;

  useEffect(() => {
    if (current) loadTags(tracking.tags, current);
  }, [current, tracking.tags]);

  const choose = useCallback(
    (choice: ConsentChoice, withdrawing = false) => {
      const previous = current;
      const visitorId = previous?.visitorId ?? crypto.randomUUID();
      const next: StoredConsent = {
        ...choice,
        version: tracking.banner_version,
        visitorId,
        expiresAt: nowMs() + tracking.validity_days * 86_400_000,
      };
      document.cookie = consentCookie(slug, next, window.location.protocol === "https:");
      setStored(next);
      setSettingsOpen(false);
      void recordSiteConsent(slug, {
        visitor_id: visitorId,
        banner_version: tracking.banner_version,
        action: consentAction(choice, withdrawing),
        analytics: choice.analytics,
        marketing: choice.marketing,
      }).catch(() => undefined);
      // Scripts that already ran cannot be unloaded: a withdrawal starts the page afresh.
      if (previous && ((previous.analytics && !choice.analytics) || (previous.marketing && !choice.marketing))) {
        window.location.reload();
      }
    },
    [current, slug, tracking.banner_version, tracking.validity_days],
  );

  const value = useMemo<Ctx>(
    () => ({
      open: () => setSettingsOpen(true),
      visitorId: () => current?.visitorId ?? null,
      marketing: () => current?.marketing === true,
    }),
    [current],
  );

  return (
    <ConsentContext.Provider value={value}>
      {children}
      {needed && hydrated && !current ? (
        <div
          role="region"
          aria-label={t("consent.title")}
          data-testid="site-consent-bar"
          className="fixed inset-x-0 bottom-0 z-(--z-toast) px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
          style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}
        >
          <div className="mx-auto flex max-w-3xl flex-col gap-3">
            <p className="text-sm" style={{ color: "var(--text)" }}>
              <b>{t("consent.title")}</b> {t("consent.text")}
            </p>
            <div className="grid grid-cols-3 gap-2">
              <ConsentButton onClick={() => choose({ analytics: false, marketing: false })}>{t("consent.rejectAll")}</ConsentButton>
              <ConsentButton onClick={() => setSettingsOpen(true)}>{t("consent.settings")}</ConsentButton>
              <ConsentButton onClick={() => choose({ analytics: true, marketing: true })}>{t("consent.acceptAll")}</ConsentButton>
            </div>
          </div>
        </div>
      ) : null}
      {settingsOpen ? (
        <ConsentSettings tags={tracking.tags} initial={current ?? { analytics: false, marketing: false }} onClose={() => setSettingsOpen(false)} onSave={(choice) => choose(choice, Boolean(current))} />
      ) : null}
    </ConsentContext.Provider>
  );
}

function ConsentButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  // Equal weight on purpose (EDPB cookie banner taskforce 2023): no button stands out.
  return (
    <button type="button" onClick={onClick} className="min-h-11 rounded-2xl px-2 text-sm font-bold" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
      {children}
    </button>
  );
}

function ConsentSettings({ tags, initial, onClose, onSave }: { tags: SiteTags; initial: ConsentChoice; onClose: () => void; onSave: (choice: ConsentChoice) => void }) {
  const t = useTranslations("BoxSite");
  const [choice, setChoice] = useState(initial);
  const categories = consentCategories(tags);
  return (
    <Dialog
      onClose={onClose}
      title={t("consent.settingsTitle")}
      description={t("consent.settingsText")}
      size="md"
      testId="site-consent-settings"
      footer={
        <button type="button" onClick={() => onSave(choice)} className="min-h-11 rounded-2xl px-5 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("consent.save")}
        </button>
      }
    >
      <div className="flex flex-col gap-3">
        <Row label={t("consent.necessary")} hint={t("consent.necessaryHint")} checked disabled onChange={() => undefined} />
        {categories.analytics ? (
          <Row label={t("consent.analytics")} hint={t("consent.analyticsHint")} checked={choice.analytics} onChange={(analytics) => setChoice((value) => ({ ...value, analytics }))} />
        ) : null}
        {categories.marketing ? (
          <Row label={t("consent.marketing")} hint={t("consent.marketingHint")} checked={choice.marketing} onChange={(marketing) => setChoice((value) => ({ ...value, marketing }))} />
        ) : null}
      </div>
    </Dialog>
  );
}

function Row({ label, hint, checked, disabled = false, onChange }: { label: string; hint: string; checked: boolean; disabled?: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="flex items-start justify-between gap-4 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{label}</span>
        <span className="text-sm" style={{ color: "var(--text-soft)" }}>{hint}</span>
      </span>
      <input type="checkbox" role="switch" checked={checked} disabled={disabled} onChange={(event) => onChange(event.target.checked)} className="mt-1 h-5 w-5 shrink-0" />
    </label>
  );
}

type TagWindow = Window & {
  dataLayer?: unknown[];
  gtag?: (...args: unknown[]) => void;
  fbq?: ((...args: unknown[]) => void) & { queue?: unknown[]; loaded?: boolean; version?: string; callMethod?: (...args: unknown[]) => void; push?: unknown };
  _fbq?: unknown;
  __paleeSiteTags?: Set<string>;
};

function addScript(src: string) {
  const script = document.createElement("script");
  script.async = true;
  script.src = src;
  document.head.appendChild(script);
}

/** Loads the tags a choice allows, once each, with Consent Mode set first. */
function loadTags(tags: SiteTags, choice: ConsentChoice) {
  const w = window as TagWindow;
  const loaded = (w.__paleeSiteTags ??= new Set());
  const allowed = allowedTags(tags, choice);
  if (allowed.length === 0) return;

  w.dataLayer = w.dataLayer ?? [];
  if (!w.gtag) {
    w.gtag = function gtag() {
      // eslint-disable-next-line prefer-rest-params -- gtag reads the arguments object
      w.dataLayer!.push(arguments);
    };
    w.gtag("consent", "default", { ...CONSENT_DEFAULT });
  }
  w.gtag("consent", "update", consentModeUpdate(choice));

  for (const key of allowed) {
    const id = tags[key];
    if (!id || loaded.has(key)) continue;
    loaded.add(key);
    if (key === "ga4_measurement_id") {
      addScript(`https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(id)}`);
      w.gtag("js", new Date());
      w.gtag("config", id);
    } else if (key === "gtm_container_id") {
      w.dataLayer.push({ "gtm.start": Date.now(), event: "gtm.js" });
      addScript(`https://www.googletagmanager.com/gtm.js?id=${encodeURIComponent(id)}`);
    } else if (key === "meta_pixel_id") {
      if (!w.fbq) {
        const fbq = function (...args: unknown[]) {
          if (fbq.callMethod) fbq.callMethod(...args);
          else fbq.queue!.push(args);
        } as NonNullable<TagWindow["fbq"]>;
        fbq.queue = [];
        fbq.loaded = true;
        fbq.version = "2.0";
        fbq.push = fbq;
        w.fbq = fbq;
        w._fbq = fbq;
        addScript("https://connect.facebook.net/en_US/fbevents.js");
      }
      w.fbq("init", id);
      w.fbq("track", "PageView");
    }
  }
}

/** ADR-354 §5: the browser Pixel's Lead event, only with marketing consent. */
export function trackLead() {
  const w = window as TagWindow;
  if (w.__paleeSiteTags?.has("meta_pixel_id") && w.fbq) w.fbq("track", "Lead");
}
