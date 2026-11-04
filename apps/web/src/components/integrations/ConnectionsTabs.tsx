"use client";

import { useState, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import { SegmentPicker } from "@/components/filters/SegmentPicker";

import { ApiKeysSettings } from "./ApiKeysSettings";
import { EmailListSettings } from "./EmailListSettings";
import { WebhooksSettings } from "./WebhooksSettings";

export const CONNECTION_TABS = ["sms", "keys", "webhooks", "list"] as const;
export type ConnectionTab = (typeof CONNECTION_TABS)[number];

/**
 * Ρυθμίσεις › Συνδέσεις: Μηνύματα SMS (W3) · Κλειδιά API · Webhooks ·
 * Λίστα email (W10 screens 1–3). One tab at a time keeps the page calm.
 */
export function ConnectionsTabs({ token, sms }: { token: string; sms: ReactNode }) {
  const t = useTranslations("Connections");
  // A webhook's page links back with `?connections=webhooks`.
  const wanted = useSearchParams()?.get("connections");
  const [tab, setTab] = useState<ConnectionTab>(() => (wanted && (CONNECTION_TABS as readonly string[]).includes(wanted) ? (wanted as ConnectionTab) : "sms"));
  return (
    <div className="space-y-4" data-testid="connections-tabs">
      <SegmentPicker
        ariaLabel={t("tabsLabel")}
        idPrefix="connections"
        panelId="connections-panel"
        options={CONNECTION_TABS.map((value) => ({ value, label: t(`tab.${value}`) }))}
        value={tab}
        onChange={setTab}
      />
      <div id="connections-panel" role="tabpanel" aria-labelledby={`connections-tab-${tab}`}>
        {tab === "sms" ? sms : null}
        {tab === "keys" ? <ApiKeysSettings token={token} /> : null}
        {tab === "webhooks" ? <WebhooksSettings token={token} /> : null}
        {tab === "list" ? <EmailListSettings token={token} /> : null}
      </div>
    </div>
  );
}
