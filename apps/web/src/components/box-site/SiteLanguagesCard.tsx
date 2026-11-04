"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import type { SiteLanguages } from "@/api/box-site";
import { secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { Select } from "@/components/ui/Select";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { addableLanguages, addLanguage, languageName, progressFor, readyPercent, removeLanguage, showLanguage } from "@/lib/site-translations";

type Languages = { translation_locales: string[]; visible_locales: string[] };

/**
 * «Γλώσσες ιστοσελίδας» (ADR-500, ANR picked A): the box's own language,
 * each translation with how far it is, a switch that shows it to visitors,
 * and the way into «Μεταφράσεις». A new language starts hidden.
 */
export function SiteLanguagesCard({
  languages,
  value,
  onChange,
  disabled,
}: {
  languages: SiteLanguages;
  value: Languages;
  onChange: (next: Languages) => void;
  disabled?: boolean;
}) {
  const t = useTranslations("BoxSite.languages");
  const slug = useOrganizationSlug();
  const [adding, setAdding] = useState("");
  const addable = addableLanguages(languages, value.translation_locales);

  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="website-languages">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("title")}</h2>
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("hint", { language: languageName(languages.source) })}</p>

      <ul className="flex flex-col">
        <li className="flex min-h-12 flex-col justify-center py-2" data-testid="website-language-source">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{languageName(languages.source)}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("sourceHint")}</span>
        </li>
        {value.translation_locales.map((locale) => {
          const { counts, total } = progressFor(languages, locale);
          const percent = readyPercent(counts, total);
          const visible = value.visible_locales.includes(locale);
          const name = languageName(locale);
          return (
            <li key={locale} className="flex flex-col gap-2 py-3" style={{ borderTop: "1px solid var(--border)" }} data-testid={`website-language-${locale}`}>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }} lang={locale}>{name}</span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {t("progress", { ready: counts.ok, total })}
                    {counts.missing > 0 ? ` · ${t("missing", { count: counts.missing })}` : ""}
                    {counts.stale > 0 ? ` · ${t("stale", { count: counts.stale })}` : ""}
                    {counts.machine > 0 ? ` · ${t("machine", { count: counts.machine })}` : ""}
                  </span>
                </span>
                <Link
                  href={adminHref(`/admin/settings/website/translations?lang=${encodeURIComponent(locale)}`, slug)}
                  className="rounded-full px-4 py-1.5 text-sm font-semibold"
                  style={{ border: "1px solid var(--primary)", color: "var(--primary-strong)" }}
                  data-testid={`website-language-translate-${locale}`}
                >
                  {t("translate")}
                </Link>
                <input
                  type="checkbox"
                  role="switch"
                  aria-label={t("showOnSite", { language: name })}
                  checked={visible}
                  disabled={disabled}
                  onChange={(event) => onChange(showLanguage(value, locale, event.target.checked))}
                  className="h-5 w-5 shrink-0"
                  style={{ accentColor: "var(--primary)" }}
                  data-testid={`website-language-visible-${locale}`}
                />
                <MoreMenu
                  label={t("more", { language: name })}
                  items={[{ label: t("remove"), tone: "danger", onSelect: () => onChange(removeLanguage(value, locale)) }]}
                />
              </div>
              <div className="h-1.5 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }} aria-hidden="true">
                <div className="h-full rounded-full" style={{ width: `${percent}%`, background: "var(--success)" }} />
              </div>
              <p className="text-xs" style={{ color: "var(--muted)" }}>{visible ? t("visibleNote") : t("hiddenNote")}</p>
            </li>
          );
        })}
      </ul>

      {addable.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2" data-testid="website-language-add">
          <Select
            value={adding}
            onValueChange={setAdding}
            placeholder={t("addPlaceholder")}
            aria-label={t("add")}
            disabled={disabled}
            className="min-w-48 rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {addable.map((locale) => (
              <option key={locale} value={locale}>
                {languageName(locale)}
              </option>
            ))}
          </Select>
          <button
            type="button"
            disabled={!adding || disabled}
            onClick={() => {
              onChange(addLanguage(value, adding));
              setAdding("");
            }}
            className={secondaryButtonClass}
            style={secondaryButtonStyle}
          >
            {t("add")}
          </button>
        </div>
      ) : null}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("saveNote")}</p>
    </section>
  );
}
