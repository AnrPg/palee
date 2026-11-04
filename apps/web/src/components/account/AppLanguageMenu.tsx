"use client";

import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { LanguageMenu } from "@/components/ui/LanguageMenu";
import { isAppLocale, SUPPORTED_LOCALES } from "@/i18n/locales";

import { useAppLanguage } from "./use-app-language";

/** ADR-545: «🇬🇷 EL» at the top right of «Εγώ»; two presses change the app's language. */
export function AppLanguageMenu() {
  const language = useAppLanguage();
  return (
    <span className="flex flex-col items-end gap-1">
      <LanguageMenu
        value={language.value}
        options={SUPPORTED_LOCALES}
        pending={language.pending}
        onChoose={(code) => {
          if (isAppLocale(code)) void language.choose(code);
        }}
        testId="app-language-menu"
      />
      {language.error ? <ErrorNotice>{language.error}</ErrorNotice> : null}
    </span>
  );
}
