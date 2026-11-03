"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchCalendarExportLinks } from "@/api/calendar";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { googleCalendarUrl, rememberCalendarOffer } from "@/lib/training-floor";

/**
 * ADR-359 (ANR mockup e4 A): right after the first booking, once, «Να μπαίνουν
 * οι κρατήσεις στο ημερολόγιό σου;». It subscribes the calendar to the private
 * feed, where bookings update and cancellations disappear by themselves. Any
 * answer, «Όχι τώρα» included, is final; the feed stays in Εγώ › Συνδεδεμένες
 * συσκευές.
 */
export function CalendarOfferSheet({ userId, onClose }: { userId: string; onClose: () => void }) {
  const t = useTranslations("TrainingFloor");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const links = useQuery({
    queryKey: ["calendar", "export-links"],
    enabled: Boolean(token),
    queryFn: () => fetchCalendarExportLinks(token!),
    staleTime: 5 * 60_000,
  });
  const answer = (choice: "apple" | "google" | "no") => {
    rememberCalendarOffer(userId, choice);
    onClose();
  };
  const webcal = links.data?.webcal_url ?? null;

  return (
    <Dialog
      onClose={() => answer("no")}
      title={t("calendarOfferTitle")}
      description={t("calendarOfferHint")}
      titleId="calendar-offer-title"
      size="md"
    >
      <div className="flex flex-col gap-2" data-testid="calendar-offer">
        {links.isError ? <ErrorNotice>{t("calendarOfferError")}</ErrorNotice> : null}
        <a
          href={webcal ?? undefined}
          aria-disabled={!webcal}
          onClick={(event) => {
            if (!webcal) {
              event.preventDefault();
              return;
            }
            answer("apple");
          }}
          className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)", opacity: webcal ? 1 : 0.5 }}
        >
          {t("calendarOfferApple")}
        </a>
        <a
          href={webcal ? googleCalendarUrl(webcal) : undefined}
          target="_blank"
          rel="noopener noreferrer"
          aria-disabled={!webcal}
          onClick={(event) => {
            if (!webcal) {
              event.preventDefault();
              return;
            }
            answer("google");
          }}
          className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ border: "1px solid var(--border)", color: "var(--text)", opacity: webcal ? 1 : 0.5 }}
        >
          {t("calendarOfferGoogle")}
        </a>
        <button
          type="button"
          onClick={() => answer("no")}
          className="min-h-11 text-sm font-semibold"
          style={{ color: "var(--muted)" }}
        >
          {t("calendarOfferNotNow")}
        </button>
      </div>
    </Dialog>
  );
}
