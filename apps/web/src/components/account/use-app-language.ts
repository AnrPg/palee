"use client";

import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { updateProfile } from "@/api/profile";
import { useSession } from "@/components/session-provider";
import { isAppLocale, persistLocaleCookie, type AppLocale } from "@/i18n/locales";

/**
 * The signed-in person's app language (ADR-195/545): saved on the account,
 * written to the locale cookie, then the page reloads in it. Shared by the
 * «Εγώ» language button and Ρυθμίσεις › Γλώσσα.
 */
export function useAppLanguage() {
  const tProfile = useTranslations("Profile");
  const locale = useLocale();
  const { tokens, currentUser } = useSession();
  const preferred = (currentUser as { preferred_locale?: string } | null)?.preferred_locale;
  const value: AppLocale = isAppLocale(preferred) ? preferred : isAppLocale(locale) ? locale : "en";
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function choose(next: AppLocale) {
    if (!tokens || next === preferred) return;
    setError(null);
    setPending(true);
    try {
      const result = await updateProfile(tokens.access_token, { preferred_locale: next });
      window.dispatchEvent(new CustomEvent(SESSION_UPDATED_EVENT, { detail: { tokens, currentUser: { ...currentUser, ...result.user } } }));
      persistLocaleCookie(next);
      window.location.reload();
    } catch {
      setError(tProfile("languageError"));
      setPending(false);
    }
  }

  return { value, pending, error, choose };
}
