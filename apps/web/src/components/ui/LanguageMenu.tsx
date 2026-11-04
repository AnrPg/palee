"use client";

import { useTranslations } from "next-intl";
import { useState, type CSSProperties } from "react";

import { currentFirst, languageDir, languageShortCode, nativeLanguageName } from "@/lib/language-flags";

import { Dialog } from "./Dialog";
import { LanguageFlag } from "./LanguageFlag";

/**
 * ADR-545: the one language switch of the app and of a box's website. A
 * button with the current flag and code («🇬🇷 EL») opens a list: the current
 * language first, then the others, each row a flag, its ISO code and the
 * language's name in its own script. Two presses from the screen it is on.
 *
 * Pass `hrefFor` when each language has its own address (a website): the
 * rows are links. Otherwise `onChoose` gets the chosen code.
 */
export function LanguageMenu({
  value,
  options,
  onChoose,
  hrefFor,
  pending = false,
  tone = "panel",
  testId = "language-menu",
}: {
  value: string;
  options: readonly string[];
  onChoose?: (code: string) => void;
  hrefFor?: (code: string) => string;
  pending?: boolean;
  /** `media` sits on a photo (the box's page header). */
  tone?: "panel" | "media";
  testId?: string;
}) {
  const t = useTranslations("LanguageMenu");
  const [open, setOpen] = useState(false);
  const ordered = currentFirst(options, value);
  const others = ordered.filter((code) => code !== value);
  const hasCurrent = ordered[0] === value;
  const buttonStyle: CSSProperties =
    tone === "media"
      ? { background: "var(--media-control)", color: "var(--on-media)" }
      : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };

  function choose(code: string) {
    setOpen(false);
    if (code !== value) onChoose?.(code);
  }

  const row = (code: string, current: boolean) => {
    const content = (
      <>
        <LanguageFlag code={code} size={24} />
        <span className="w-8 shrink-0 font-mono text-xs font-bold" style={{ color: "var(--muted)" }}>
          {languageShortCode(code)}
        </span>
        <span className="min-w-0 flex-1 truncate text-sm font-bold" lang={code} dir={languageDir(code)}>
          {nativeLanguageName(code)}
        </span>
        <span aria-hidden="true" className="w-4 shrink-0 font-black" style={{ color: "var(--primary)" }}>
          {current ? "✓" : ""}
        </span>
      </>
    );
    const className = "flex min-h-12 w-full items-center gap-3 rounded-xl px-3 text-start";
    const style: CSSProperties = current
      ? { background: "color-mix(in srgb, var(--primary) 10%, var(--panel))", color: "var(--text)" }
      : { color: "var(--text)" };
    return (
      <li key={code}>
        {hrefFor ? (
          <a
            href={hrefFor(code)}
            hrefLang={code}
            aria-current={current ? "page" : undefined}
            onClick={() => choose(code)}
            className={className}
            style={style}
            data-testid={`${testId}-option-${code}`}
          >
            {content}
          </a>
        ) : (
          <button
            type="button"
            aria-current={current ? "true" : undefined}
            disabled={pending}
            onClick={() => choose(code)}
            className={`${className} disabled:opacity-50`}
            style={style}
            data-testid={`${testId}-option-${code}`}
          >
            {content}
          </button>
        )}
      </li>
    );
  };

  return (
    <>
      <button
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={t("button", { language: nativeLanguageName(value) })}
        disabled={pending}
        onClick={() => setOpen(true)}
        className="inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full px-3 text-xs font-extrabold disabled:opacity-60"
        style={buttonStyle}
        data-testid={testId}
      >
        <LanguageFlag code={value} size={20} />
        <span>{languageShortCode(value)}</span>
        <span aria-hidden="true" className="text-[10px] opacity-70">
          ▾
        </span>
      </button>
      {open ? (
        <Dialog onClose={() => setOpen(false)} title={t("title")} size="sm" variant="sheet" testId={`${testId}-list`}>
          <div className="grid gap-1">
            {hasCurrent ? (
              <>
                <p className="px-3 pt-1 text-[11px] font-bold uppercase tracking-wider" style={{ color: "var(--muted)" }}>
                  {t("current")}
                </p>
                <ul>{row(value, true)}</ul>
              </>
            ) : null}
            {others.length ? (
              <>
                <p className="px-3 pt-2 text-[11px] font-bold uppercase tracking-wider" style={{ color: "var(--muted)" }}>
                  {t("others")}
                </p>
                <ul className="grid gap-0.5">{others.map((code) => row(code, false))}</ul>
              </>
            ) : null}
          </div>
        </Dialog>
      ) : null}
    </>
  );
}
