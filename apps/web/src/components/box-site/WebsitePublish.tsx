"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  discardSiteDraft,
  fetchSitePreview,
  publishSite,
  saveSite,
  type AdminSite,
  type SiteSettingsUpdate,
  type SiteSettingsV2,
} from "@/api/box-site";
import { fetchPublicBox } from "@/api/social";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { BoxWebsite } from "./templates/BoxWebsite";
import type { SitePage } from "./templates/site-model";
import { changedGroups, effectiveSite, type LooseSiteSettings, type SiteDraftPatch } from "./website-draft-model";

export const SITE_KEY = ["admin", "site"] as const;
export const PREVIEW_KEY = ["admin", "site", "preview"] as const;

const keysOf = (patch: SiteDraftPatch) => Object.keys(patch) as (keyof SiteDraftPatch)[];

/**
 * ADR-530 §2: each click on the look or a section switch goes to
 * `PUT /admin/site`, which keeps it as a draft. Clicks made while a save is
 * on its way wait and go together in the next one, with the newest
 * `lock_version`, so fast clicking never trips over itself. Until the server
 * answers, the page shows the click already.
 */
export function useSiteDraft(token: string, settings: LooseSiteSettings) {
  const queryClient = useQueryClient();
  const [pending, setPending] = useState<SiteDraftPatch>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const queue = useRef<SiteDraftPatch>({});
  const inflight = useRef(false);

  const flush = useCallback(async () => {
    if (inflight.current || keysOf(queue.current).length === 0) return;
    const body = queue.current;
    queue.current = {};
    inflight.current = true;
    setSaving(true);
    try {
      const current = queryClient.getQueryData<AdminSite>(SITE_KEY);
      const lock_version = current?.settings.lock_version ?? settings.lock_version;
      const saved = await saveSite(token, { lock_version, ...body } as SiteSettingsUpdate);
      queryClient.setQueryData<AdminSite>(SITE_KEY, (site) => (site ? { ...site, settings: saved.settings, languages: saved.languages } : site));
      // What the server has now is shown from its answer; clicks still queued stay on top.
      setPending((shown) => Object.fromEntries(Object.entries(shown).filter(([key]) => key in queue.current)) as SiteDraftPatch);
      void queryClient.invalidateQueries({ queryKey: PREVIEW_KEY });
    } catch (failure) {
      queue.current = {};
      setPending({});
      setError(failure ?? new Error());
      void queryClient.invalidateQueries({ queryKey: SITE_KEY });
    } finally {
      inflight.current = false;
      setSaving(false);
      if (keysOf(queue.current).length > 0) void flush();
    }
  }, [queryClient, settings.lock_version, token]);

  const change = useCallback(
    (patch: SiteDraftPatch) => {
      setError(null);
      setPending((shown) => ({ ...shown, ...patch }));
      queue.current = { ...queue.current, ...patch };
      void flush();
    },
    [flush],
  );

  const busy = saving || keysOf(pending).length > 0;
  return {
    effective: effectiveSite(settings, pending),
    changed: changedGroups(settings, pending),
    change,
    busy,
    error,
    reset: () => {
      queue.current = {};
      setPending({});
    },
  };
}

/** The sticky bar under the settings: what is not published yet, «Απόρριψη» and «Δημοσίευση». */
export function PublishBar({
  token,
  draft,
  onPreview,
}: {
  token: string;
  draft: ReturnType<typeof useSiteDraft>;
  /** Narrow screens: opens the preview as a sheet. */
  onPreview?: () => void;
}) {
  const t = useTranslations("WebsiteLook");
  const ui = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const apply = (settings: SiteSettingsV2) => {
    queryClient.setQueryData<AdminSite>(SITE_KEY, (site) => (site ? { ...site, settings } : site));
    void queryClient.invalidateQueries({ queryKey: PREVIEW_KEY });
  };
  const publish = useMutation({
    mutationFn: () => publishSite(token),
    onSuccess: (data) => {
      draft.reset();
      apply(data.settings);
    },
  });
  const discard = useMutation({
    mutationFn: () => discardSiteDraft(token),
    onSuccess: (data) => {
      draft.reset();
      apply(data.settings);
      setConfirming(false);
      publish.reset();
    },
  });
  const changed = draft.changed;
  // «Δημοσιεύτηκε» after a publish, while nothing new waits.
  const published = publish.isSuccess && changed.length === 0;

  const list = new Intl.ListFormat(locale, { type: "unit", style: "short" }).format(changed.map((group) => t(`publish.groups.${group}`)));
  const failure = publish.error ?? discard.error ?? draft.error;
  const working = draft.busy || publish.isPending || discard.isPending;
  const text = changed.length > 0 ? t("publish.pending", { list }) : published ? t("publish.published") : t("publish.allPublished");

  return (
    <div
      className="flex flex-col gap-2 rounded-[1.5rem] border px-5 py-3.5"
      style={{ background: "var(--panel)", borderColor: "var(--border)", boxShadow: "var(--shadow-md)" }}
      data-testid="website-publish-bar"
    >
      <div className="flex flex-wrap items-center gap-3">
        <span className="flex min-w-0 flex-1 items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {changed.length > 0 ? <span aria-hidden className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: "var(--warning)" }} /> : null}
          <span role="status" data-testid="website-publish-status" style={published ? { color: "var(--success)" } : undefined}>
            {text}
          </span>
        </span>
        {onPreview ? (
          <button
            type="button"
            onClick={onPreview}
            className="min-h-11 rounded-full px-4 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="website-preview-open"
          >
            {t("preview.open")}
          </button>
        ) : null}
        {changed.length > 0 ? (
          <button
            type="button"
            disabled={working}
            onClick={() => (changed.length > 1 ? setConfirming(true) : discard.mutate())}
            className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
            data-testid="website-discard"
          >
            {t("publish.discard")}
          </button>
        ) : null}
        <button
          type="button"
          disabled={working || changed.length === 0}
          onClick={() => publish.mutate()}
          className="min-h-11 rounded-full px-5 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          data-testid="website-publish"
        >
          {publish.isPending ? t("publish.publishing") : t("publish.publish")}
        </button>
      </div>
      {failure ? <ErrorNotice variant="field">{localizeError(failure, ui)}</ErrorNotice> : null}
      {confirming ? (
        <Dialog
          onClose={() => setConfirming(false)}
          title={t("publish.discardTitle")}
          size="sm"
          variant="center"
          dismissible={!discard.isPending}
          testId="website-discard-confirm"
          footer={
            <>
              <button type="button" onClick={() => setConfirming(false)} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
                {t("publish.keep")}
              </button>
              <button
                type="button"
                disabled={discard.isPending}
                onClick={() => discard.mutate()}
                className="min-h-11 rounded-full px-5 text-sm font-bold disabled:opacity-60"
                style={{ background: "var(--danger-surface)", border: "1px solid var(--danger-border)", color: "var(--danger-strong)" }}
                data-testid="website-discard-yes"
              >
                {t("publish.discard")}
              </button>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("publish.discardText", { list })}</p>
        </Dialog>
      ) : null}
    </div>
  );
}

const WIDE = "(min-width: 1100px)";

/** True from 1100px up: the preview sits beside the settings instead of opening as a sheet. */
export function useWideLayout() {
  return useSyncExternalStore(
    (notify) => {
      if (typeof window === "undefined" || !window.matchMedia) return () => undefined;
      const query = window.matchMedia(WIDE);
      query.addEventListener("change", notify);
      return () => query.removeEventListener("change", notify);
    },
    () => (typeof window !== "undefined" && window.matchMedia ? window.matchMedia(WIDE).matches : false),
    () => false,
  );
}

const DESK_WIDTH = 1280;
const FRAME_HEIGHT = 680;

/** The panel's width, for scaling the desktop frame down to fit. */
function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    setWidth(element.clientWidth);
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => setWidth(element.clientWidth));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return { ref, width };
}

/**
 * «Προεπισκόπηση»: the website as it will look after «Δημοσίευση», drawn by
 * the same components visitors get (ADR-530 §2). Links switch pages inside
 * the frame and forms do not send.
 */
export function SitePreview({ token, slug, look }: { token: string; slug: string; look: Pick<SiteSettingsV2, "template" | "palette" | "appearance" | "calm_motion"> }) {
  const t = useTranslations("WebsiteLook");
  const [device, setDevice] = useState<"phone" | "desk">("phone");
  const [pageKey, setPageKey] = useState<SitePage>("home");
  const preview = useQuery({ queryKey: PREVIEW_KEY, enabled: Boolean(token), queryFn: () => fetchSitePreview(token), retry: false });
  const box = useQuery({ queryKey: ["public-box", slug], enabled: Boolean(slug), queryFn: () => fetchPublicBox(slug), retry: false });
  const { ref, width } = useWidth();
  const scale = width > 0 ? Math.min(1, width / DESK_WIDTH) : 0.5;
  const devices = ["phone", "desk"] as const;

  const site = preview.data ? { ...preview.data, ...look } : null;
  const body =
    site && box.data ? (
      <BoxWebsite page={box.data} site={site} language="box" basePath="" standalone={false} pageKey={pageKey} preview={{ device, onNavigate: setPageKey }} />
    ) : (
      <p className="p-6 text-sm" style={{ color: "var(--muted)" }}>
        {preview.isError || box.isError ? t("preview.unavailable") : t("preview.loading")}
      </p>
    );

  return (
    <div className="flex flex-col gap-3" data-testid="website-preview">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="flex flex-col">
          <b className="text-sm" style={{ color: "var(--text)" }}>{t("preview.title")}</b>
          <span className="text-xs" style={{ color: "var(--muted)" }}>{t("preview.hint")}</span>
        </span>
        <div role="radiogroup" aria-label={t("preview.device")} className="flex gap-1.5">
          {devices.map((key) => (
            <button
              key={key}
              type="button"
              role="radio"
              aria-checked={device === key}
              onClick={() => setDevice(key)}
              className="min-h-9 rounded-full px-3.5 text-sm"
              style={
                device === key
                  ? { background: "var(--spark)", color: "var(--spark-contrast)", border: "1px solid transparent", fontWeight: 700 }
                  : { background: "transparent", color: "var(--text)", border: "1px solid var(--border)" }
              }
              data-testid={`website-preview-${key}`}
            >
              {t(`preview.${key}`)}
            </button>
          ))}
        </div>
      </div>
      <div ref={ref} className="w-full">
        {device === "phone" ? (
          <div className="mx-auto w-full max-w-[390px] overflow-y-auto overflow-x-hidden rounded-[2rem]" style={{ height: FRAME_HEIGHT, maxHeight: "75dvh", border: "6px solid var(--text)", background: "var(--bg)" }}>
            {body}
          </div>
        ) : (
          <div className="relative w-full overflow-hidden rounded-2xl" style={{ height: FRAME_HEIGHT, maxHeight: "75dvh", border: "1px solid var(--border)", background: "var(--bg)" }}>
            <div
              className="absolute left-0 top-0 overflow-y-auto overflow-x-hidden"
              style={{ width: DESK_WIDTH, height: `calc(100% / ${scale})`, transform: `scale(${scale})`, transformOrigin: "top left" }}
            >
              {body}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/** Narrow screens: the preview as a full-screen sheet. */
export function PreviewSheet({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  const t = useTranslations("WebsiteLook");
  return (
    <Dialog onClose={onClose} title={t("preview.title")} variant="screen" size="full" testId="website-preview-sheet">
      {children}
    </Dialog>
  );
}
