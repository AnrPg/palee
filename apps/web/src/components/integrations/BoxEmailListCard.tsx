"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchMarketingConsent, marketingConsentKey, saveMarketingConsent } from "@/api/integrations";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { HubCard } from "@/components/member-app/HubParts";
import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Box › Ειδοποιήσεις › «Ενημερώσεις με email» (W10 screen 3, option A;
 * ADR-380): the member's own yes or no to the box's newsletters and offers.
 * Off until they say yes; staff cannot change it. Shown only when the box
 * has connected an email list. It sits next to W3's SMS switches (the
 * mockup put it under Προφίλ › Ειδοποιήσεις; the box's own consents already
 * live in Box, so it joins them there).
 */
export function BoxEmailListCard({ membership }: BoxExtensionProps) {
  const t = useTranslations("Connections");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const slug = membership.organization.slug;
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: marketingConsentKey(slug), queryFn: () => fetchMarketingConsent(token!, slug), enabled: Boolean(token) });
  const save = useMutation({
    mutationFn: (granted: boolean) => saveMarketingConsent(token!, slug, granted),
    onSuccess: (next) => queryClient.setQueryData(marketingConsentKey(slug), next),
  });
  if (!token || !query.data?.list_connected) return null;
  const consent = query.data;
  const boxName = membership.settings?.brand_name?.trim() || membership.organization.name;

  return (
    <HubCard eyebrow={t("memberEyebrow")}>
      <div className="flex items-start gap-3" data-testid="box-email-consent">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("memberEmailTitle", { box: boxName })}</p>
          <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>{t("memberEmailHint")}</p>
          {consent.granted && consent.granted_at ? (
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
              {t("memberEmailSince", { when: new Date(consent.granted_at).toLocaleString(locale, { dateStyle: "short", timeStyle: "short", hourCycle: "h23" }) })}
            </p>
          ) : null}
        </div>
        <Toggle label={t("memberEmailTitle", { box: boxName })} checked={consent.granted} disabled={save.isPending} onChange={(value) => save.mutate(value)} />
      </div>
      {save.isError ? <ErrorNotice variant="field">{t("errors.generic")}</ErrorNotice> : null}
    </HubCard>
  );
}
