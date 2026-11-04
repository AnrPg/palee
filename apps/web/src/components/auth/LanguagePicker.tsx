"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";

import { LanguageMenu } from "@/components/ui/LanguageMenu";
import { isAppLocale, persistLocaleCookie, SUPPORTED_LOCALES } from "@/i18n/locales";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * ADR-195/545: the language switch on the signed-out pages (sign in, sign up,
 * password reset, business sign-up): the same «🇬🇷 EL» button as «Εγώ». It
 * writes the locale cookie the profile setting writes and re-renders in
 * place, so what the person already typed stays. Sign-up sends this
 * language as the new account's own.
 */
export function LanguagePicker({ className = "" }: { className?: string }) {
  const locale = useUiLocale();
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function choose(next: string) {
    if (!isAppLocale(next) || next === locale) return;
    persistLocaleCookie(next);
    startTransition(() => router.refresh());
  }

  return (
    <div className={`inline-flex items-center ${className}`} data-language-picker>
      <LanguageMenu value={locale} options={SUPPORTED_LOCALES} onChoose={choose} pending={pending} testId="auth-language-menu" />
    </div>
  );
}
