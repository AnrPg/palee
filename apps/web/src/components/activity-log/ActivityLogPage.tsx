"use client";

import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";

import { PageHeader } from "@/components/PageHeader";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { canReadActivityLog } from "./activity-log-model";
import { ActivityLogList } from "./ActivityLogList";

/**
 * Διαχείριση › Αρχείο ενεργειών (ADR-760, 1A): who on the staff did what,
 * when, to whom and why. `?person=<id>&name=<name>` opens it filtered to one
 * person (the profile's «Όλο το αρχείο →»).
 */
export function ActivityLogPage() {
  const t = useTranslations("ActivityLog");
  const slug = useOrganizationSlug();
  const searchParams = useSearchParams();
  const { membership, isLoading } = useSelectedMembershipRole();
  const personId = searchParams.get("person");
  const initialPerson = personId ? { id: personId, name: searchParams.get("name") || t("onePerson") } : null;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <BackLink href={adminHref("/admin", slug)}>{t("back")}</BackLink>
        <PageHeader title={t("title")} />
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("intro")}</p>
        {isLoading ? null : canReadActivityLog(membership) ? (
          <ActivityLogList initialPerson={initialPerson} />
        ) : (
          <ErrorNotice>{t("forbidden")}</ErrorNotice>
        )}
      </div>
    </main>
  );
}
