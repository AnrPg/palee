"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";

import {
  fetchSiteTranslations,
  getSite,
  keepSiteTranslations,
  machineTranslateSite,
  saveSiteTranslations,
  siteTranslationsKey,
  type SiteTranslationItem,
  type SiteTranslations as Page,
  type SiteTranslationStatus,
} from "@/api/box-site";
import { useSession } from "@/components/session-provider";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { BackLink } from "@/components/ui/BackLink";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import {
  filterCounts,
  groupItems,
  languageName,
  machineDue,
  readyPercent,
  sourceEditPath,
  TRANSLATION_FILTERS,
  workQueue,
  type TranslationFilter,
} from "@/lib/site-translations";

const SITE_KEY = ["admin", "site"] as const;

const STATUS_STYLE: Record<SiteTranslationStatus, { background: string; color: string }> = {
  ok: { background: "color-mix(in srgb, var(--success) 14%, transparent)", color: "var(--success)" },
  missing: { background: "var(--panel-muted)", color: "var(--muted)" },
  stale: { background: "color-mix(in srgb, var(--warning) 16%, transparent)", color: "var(--warning)" },
  machine: { background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary-strong)" },
};

/**
 * «Μεταφράσεις» (ADR-500, ANR picked A): every text the box wrote for its
 * website, its own text beside the translation, with a status each. A
 * person's text saves when the field is left; «Αυτόματη μετάφραση» fills
 * only what is missing or out of date; «Ένα-ένα» walks through what is left.
 */
export function SiteTranslations() {
  const t = useTranslations("BoxSite.translations");
  const ui = useUiTranslations();
  const params = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const site = useQuery({ queryKey: SITE_KEY, enabled: Boolean(token), queryFn: () => getSite(token) });
  const chosen = site.data?.settings.translation_locales ?? [];
  const locale = params.get("lang") || chosen[0] || "en";
  const page = useQuery({ queryKey: siteTranslationsKey(locale), enabled: Boolean(token), queryFn: () => fetchSiteTranslations(token, locale) });
  const [filter, setFilter] = useState<TranslationFilter>("todo");
  const [oneByOne, setOneByOne] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const store = (next: Page) => {
    queryClient.setQueryData(siteTranslationsKey(locale), next);
    void queryClient.invalidateQueries({ queryKey: SITE_KEY });
  };
  const machine = useMutation({
    mutationFn: () => machineTranslateSite(token, locale),
    onSuccess: (next) => {
      store(next);
      setFilter("machine");
      setNotice(t("machineDone", { count: next.written ?? 0 }));
    },
  });

  const data = page.data;
  const name = languageName(locale);
  const settingsHref = adminHref("/admin/settings/website", slug);
  const hidden = site.data ? !site.data.settings.visible_locales.includes(locale) : false;
  const notChosen = site.data ? !chosen.includes(locale) : false;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }} data-testid="site-translations">
      <div className="mx-auto flex max-w-4xl flex-col gap-5">
        <header className="flex flex-col gap-2">
          <BackLink href={settingsHref} className="self-start text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("back")}
          </BackLink>
          <h1 className="text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("title")}</h1>
          <p className="max-w-2xl text-sm" style={{ color: "var(--muted)" }}>
            {t("intro", { source: data ? languageName(data.source_language) : "", language: name })}
          </p>
        </header>

        {chosen.length > 1 || notChosen ? (
          <nav className="flex flex-wrap gap-2" aria-label={t("languages")} data-testid="site-translations-languages">
            {(notChosen ? [...chosen, locale] : chosen).map((code) => (
              <Link
                key={code}
                href={adminHref(`/admin/settings/website/translations?lang=${encodeURIComponent(code)}`, slug)}
                aria-current={code === locale ? "page" : undefined}
                className="rounded-full px-3 py-1.5 text-xs font-semibold"
                style={code === locale ? { background: "var(--text)", color: "var(--bg)" } : { border: "1px solid var(--border)", color: "var(--text-soft)" }}
                lang={code}
              >
                {languageName(code)}
              </Link>
            ))}
          </nav>
        ) : null}

        {notChosen ? (
          <Banner>
            {t("notChosen", { language: name })}{" "}
            <Link href={settingsHref} className="font-semibold" style={{ color: "var(--primary-strong)" }}>{t("openLanguages")}</Link>
          </Banner>
        ) : hidden ? (
          <Banner testId="site-translations-hidden">
            {t("hiddenLanguage", { language: name })}{" "}
            <Link href={settingsHref} className="font-semibold" style={{ color: "var(--primary-strong)" }}>{t("openLanguages")}</Link>
          </Banner>
        ) : null}

        {page.isPending ? <StatusText tone="muted">{t("loading")}</StatusText> : null}
        {page.isError ? <StatusText tone="error">{localizeError(page.error, ui)}</StatusText> : null}

        {data ? (
          <section className="flex flex-col gap-4 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex flex-col gap-1.5">
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <b style={{ color: "var(--text)" }} lang={locale}>{name}</b>
                <span style={{ color: "var(--dim)" }} data-testid="site-translations-progress">{t("progress", { ready: data.counts.ok, total: data.total })}</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }} aria-hidden="true">
                <div className="h-full rounded-full" style={{ width: `${readyPercent(data.counts, data.total)}%`, background: "var(--success)" }} />
              </div>
            </div>

            {data.total === 0 ? (
              <p className="py-6 text-center text-sm" style={{ color: "var(--muted)" }}>{t("nothing")}</p>
            ) : oneByOne ? (
              <OneByOne token={token} page={data} onPage={store} onClose={() => setOneByOne(false)} />
            ) : (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  <div className="flex flex-wrap gap-1.5" role="group" aria-label={t("filterLabel")}>
                    {TRANSLATION_FILTERS.map((key) => (
                      <button
                        key={key}
                        type="button"
                        aria-pressed={filter === key}
                        onClick={() => setFilter(key)}
                        className="rounded-full px-3 py-1.5 text-xs font-semibold"
                        style={filter === key ? { background: "var(--text)", color: "var(--bg)" } : { border: "1px solid var(--border)", color: "var(--text-soft)" }}
                        data-testid={`site-translations-filter-${key}`}
                      >
                        {t(`filters.${key}`, { count: filterCounts(data.counts, data.total)[key] })}
                      </button>
                    ))}
                  </div>
                  <span className="flex-1" />
                  {filterCounts(data.counts, data.total).todo > 0 ? (
                    <button type="button" onClick={() => setOneByOne(true)} className={secondaryButtonClass} style={secondaryButtonStyle} data-testid="site-translations-one-by-one">
                      {t("oneByOne")}
                    </button>
                  ) : null}
                  {data.machine_available && machineDue(data.counts) > 0 ? (
                    <button type="button" disabled={machine.isPending} onClick={() => machine.mutate()} className={primaryButtonClass} style={primaryButtonStyle} data-testid="site-translations-machine">
                      {machine.isPending ? t("machineWorking") : t("machine", { count: machineDue(data.counts) })}
                    </button>
                  ) : null}
                </div>
                {machine.isError ? <StatusText tone="error">{localizeError(machine.error, ui)}</StatusText> : null}
                {notice && !machine.isPending ? <StatusText tone="success">{notice}</StatusText> : null}
                <TranslationList token={token} page={data} filter={filter} onPage={store} />
              </>
            )}
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("notTranslated")}</p>
          </section>
        ) : null}
      </div>
    </main>
  );
}

function Banner({ children, testId }: { children: React.ReactNode; testId?: string }) {
  return (
    <p className="rounded-2xl px-4 py-3 text-sm" style={{ border: "1px dashed var(--border-strong)", color: "var(--text-soft)" }} data-testid={testId}>
      {children}
    </p>
  );
}

function TranslationList({ token, page, filter, onPage }: { token: string; page: Page; filter: TranslationFilter; onPage: (page: Page) => void }) {
  const t = useTranslations("BoxSite.translations");
  const slug = useOrganizationSlug();
  const groups = useMemo(() => groupItems(page.items, filter), [page.items, filter]);
  if (groups.length === 0) {
    return (
      <p className="py-6 text-center text-sm" style={{ color: "var(--muted)" }} data-testid="site-translations-empty">
        {filter === "all" || filter === "todo" ? t("allDone", { language: languageName(page.locale) }) : t("noneHere")}
      </p>
    );
  }
  return (
    <div className="flex flex-col gap-2" data-testid="site-translations-list">
      {groups.map(({ group, items }) => (
        <section key={group} className="flex flex-col" data-testid={`site-translations-group-${group}`}>
          <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 pb-1.5 pt-3">
            <h2 className="text-xs font-bold uppercase tracking-wider" style={{ color: "var(--dim)" }}>{t(`groups.${group}`)}</h2>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{items.length}</span>
            {group === "about" || group === "faq" || group === "rooms" || group === "classes" ? (
              <Link href={adminHref(sourceEditPath(items[0]!), slug)} className="ms-auto text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>
                {t("editSource", { language: languageName(page.source_language) })} ›
              </Link>
            ) : null}
          </div>
          {items.map((item) => (
            <TranslationRow key={item.key} token={token} page={page} item={item} onPage={onPage} />
          ))}
        </section>
      ))}
    </div>
  );
}

function fieldLabel(t: ReturnType<typeof useTranslations>, item: SiteTranslationItem) {
  const field = t(`fields.${item.field}`, { number: item.label ?? "" });
  return item.label && item.group !== "faq" ? `${field} · ${item.label}` : field;
}

function TranslationRow({ token, page, item, onPage }: { token: string; page: Page; item: SiteTranslationItem; onPage: (page: Page) => void }) {
  const t = useTranslations("BoxSite.translations");
  const ui = useUiTranslations();
  const slug = useOrganizationSlug();
  const [text, setText] = useState(item.text ?? "");
  const focused = useRef(false);
  // A newer server text (machine, another tab) replaces ours unless we are typing.
  useEffect(() => {
    if (!focused.current) setText(item.text ?? "");
  }, [item.text]);

  const save = useMutation({
    mutationFn: (value: string) => saveSiteTranslations(token, page.locale, [{ kind: item.kind, id: item.id, field: item.field, text: value }]),
    onSuccess: onPage,
  });
  const keep = useMutation({ mutationFn: () => keepSiteTranslations(token, page.locale, [item.key]), onSuccess: onPage });
  const changed = text.trim() !== (item.text ?? "").trim();
  const label = fieldLabel(t, item);
  const perItemEdit = item.group === "packages" || item.group === "events" || item.group === "locations";

  return (
    <div className="grid gap-3 py-3 md:grid-cols-2" style={{ borderTop: "1px solid var(--border)" }} data-testid={`site-translation-${item.key}`} data-status={item.status}>
      <div className="flex min-w-0 flex-col gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {label} · {languageName(page.source_language)}
        </span>
        <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }} lang={page.source_language}>{item.source}</p>
        {perItemEdit ? (
          <Link href={adminHref(sourceEditPath(item), slug)} className="self-start text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>
            {t("editSource", { language: languageName(page.source_language) })} ›
          </Link>
        ) : null}
      </div>
      <div className="flex min-w-0 flex-col gap-1.5">
        <span className="flex flex-wrap items-center gap-2 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {languageName(page.locale)}
          <StatusBadge status={item.status} />
          {save.isPending ? <span>{t("saving")}</span> : save.isSuccess && !changed ? <span style={{ color: "var(--success)" }}>{t("saved")}</span> : null}
        </span>
        <textarea
          value={text}
          rows={item.source.length > 90 ? 4 : 1}
          lang={page.locale}
          aria-label={t("fieldIn", { field: label, language: languageName(page.locale) })}
          placeholder={t("placeholder")}
          onFocus={() => {
            focused.current = true;
          }}
          onChange={(event) => setText(event.target.value)}
          onBlur={() => {
            focused.current = false;
            if (changed) save.mutate(text);
          }}
          className={inputClass}
          style={{ ...inputStyle, resize: "vertical" }}
        />
        {item.status === "stale" ? <span className="text-xs" style={{ color: "var(--warning)" }}>{t("staleHint", { language: languageName(page.source_language) })}</span> : null}
        {(item.status === "machine" || item.status === "stale") && !changed ? (
          <button type="button" disabled={keep.isPending} onClick={() => keep.mutate()} className={`${secondaryButtonClass} self-start`} style={secondaryButtonStyle} data-testid={`site-translation-keep-${item.key}`}>
            {t("keep")}
          </button>
        ) : null}
        {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
        {keep.isError ? <StatusText tone="error">{localizeError(keep.error, ui)}</StatusText> : null}
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: SiteTranslationStatus }) {
  const t = useTranslations("BoxSite.translations");
  return (
    <span className="rounded-full px-2 py-0.5 text-[11px] font-bold" style={STATUS_STYLE[status]} data-testid="site-translation-status">
      {t(`status.${status}`)}
    </span>
  );
}

/** «Ένα-ένα»: what still needs the owner, one text at a time (Enter saves, Esc skips). */
function OneByOne({ token, page, onPage, onClose }: { token: string; page: Page; onPage: (page: Page) => void; onClose: () => void }) {
  const t = useTranslations("BoxSite.translations");
  const ui = useUiTranslations();
  // The queue is fixed when the view opens, so saved texts do not shift it.
  const [queue] = useState(() => workQueue(page.items).map((item) => item.key));
  const [index, setIndex] = useState(0);
  const current = page.items.find((item) => item.key === queue[index]);
  // The draft belongs to one text; moving on starts from that text's own translation.
  const [draft, setDraft] = useState<{ key: string; text: string } | null>(null);
  const text = current && draft?.key === current.key ? draft.text : (current?.text ?? "");
  const setText = (value: string) => current && setDraft({ key: current.key, text: value });

  const next = () => setIndex((value) => value + 1);
  const save = useMutation({
    mutationFn: async () => {
      if (!current) return null;
      const unchanged = text.trim() === (current.text ?? "").trim();
      if (unchanged && current.text && current.status !== "missing") return keepSiteTranslations(token, page.locale, [current.key]);
      if (!text.trim()) return null;
      return saveSiteTranslations(token, page.locale, [{ kind: current.kind, id: current.id, field: current.field, text }]);
    },
    onSuccess: (result) => {
      if (result) onPage(result);
      next();
    },
  });

  if (!current || index >= queue.length) {
    return (
      <div className="flex flex-col items-center gap-3 py-8 text-center" data-testid="site-translations-one-by-one-done">
        <b className="text-lg" style={{ color: "var(--text)" }}>{t("oneByOneDone")}</b>
        <button type="button" onClick={onClose} className={secondaryButtonClass} style={secondaryButtonStyle}>
          {t("backToList")}
        </button>
      </div>
    );
  }

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      save.mutate();
    } else if (event.key === "Escape") {
      event.preventDefault();
      next();
    }
  };

  return (
    <div className="mx-auto flex w-full max-w-xl flex-col gap-4" data-testid="site-translations-one-by-one-view">
      <div className="flex items-center justify-between gap-3 text-sm">
        <button type="button" onClick={onClose} className="font-semibold" style={{ color: "var(--text-soft)" }}>
          ‹ {t("backToList")}
        </button>
        <span style={{ color: "var(--dim)" }}>{t("left", { left: queue.length - index, total: queue.length })}</span>
      </div>
      <div className="flex flex-col gap-1">
        <span className="flex flex-wrap items-center gap-2 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t(`groups.${current.group}`)} · {fieldLabel(t, current)} · {languageName(page.source_language)}
          <StatusBadge status={current.status} />
        </span>
        <p className="whitespace-pre-line text-base" style={{ color: "var(--text)" }} lang={page.source_language}>{current.source}</p>
      </div>
      <label className="flex flex-col gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{languageName(page.locale)}</span>
        <textarea
          autoFocus
          value={text}
          rows={4}
          lang={page.locale}
          placeholder={t("placeholder")}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={onKeyDown}
          className={inputClass}
          style={{ ...inputStyle, resize: "vertical", fontSize: "1rem" }}
          data-testid="site-translations-one-by-one-field"
        />
      </label>
      {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={next} className={secondaryButtonClass} style={secondaryButtonStyle}>
          {t("skip")}
        </button>
        <span className="flex-1" />
        <button type="button" disabled={save.isPending} onClick={() => save.mutate()} className={primaryButtonClass} style={primaryButtonStyle} data-testid="site-translations-one-by-one-next">
          {t("saveNext")}
        </button>
      </div>
    </div>
  );
}
