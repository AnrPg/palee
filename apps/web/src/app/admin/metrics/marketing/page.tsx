


import {useUiTranslations} from "@/i18n/ui";
import { MarketingLinks } from "@/components/admin/analytics/MarketingLinks";

import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminMarketingPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl space-y-8">
          <section
            className="rounded-[2.4rem] p-8"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
              {i18n("analyticsMarketinga05588a")}
            </p>
            <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
              {i18n("marketingOperationsd71c522")}
            </h1>
            <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>
              {i18n("marketingStrategyIsGroupedHereManagementActionsOpend3d4d52")}
            </p>
          </section>

          <MarketingLinks />
        </div>
      </main>
    </AuthGuard>
  );
}
