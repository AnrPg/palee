import type { QueryClient } from "@tanstack/react-query";

import { fetchGuideProgress, guideProgressKey, putGuideProgress, type GuideProgressList } from "@/api/guides";
import { calendarOfferPending, rememberCalendarOffer } from "@/lib/training-floor";

/**
 * Questions asked once per person, on every device: the calendar offer at the
 * first booking (CP-E4) and the SMS question after a booking (W3 screen 2 B,
 * per box). The answer is kept with the person's walkthrough progress
 * (ADR-193), where a one-time offer fits: «completed» for a yes,
 * «dismissed» for «Όχι τώρα». The device also remembers it at once.
 */
export const CALENDAR_OFFER_GUIDE = "calendar_offer";

/** One id per box: `sms_ask_<slug>`, in the progress ids' alphabet and length. */
export function smsAskGuideId(slug: string): string {
  return `sms_ask_${slug.toLowerCase().replace(/[^a-z0-9]+/g, "_")}`.slice(0, 48);
}

async function answeredOnServer(queryClient: QueryClient, token: string, id: string): Promise<boolean> {
  const progress = await queryClient.fetchQuery({
    queryKey: guideProgressKey(),
    queryFn: () => fetchGuideProgress(token),
    staleTime: 5 * 60_000,
  });
  return progress.guides.some((entry) => entry.guide_id === id);
}

function saveAnswer(queryClient: QueryClient, token: string | null, id: string, status: "completed" | "dismissed") {
  if (!token) return;
  void putGuideProgress(token, id, { status, step: 0, version: 1 })
    .then((row) =>
      queryClient.setQueryData<GuideProgressList>(guideProgressKey(), (current) => ({
        ...current,
        guides: [...(current?.guides ?? []).filter((entry) => entry.guide_id !== row.guide_id), row],
      })),
    )
    .catch(() => undefined);
}

export async function shouldOfferCalendar(queryClient: QueryClient, token: string | null, userId: string | null | undefined): Promise<boolean> {
  if (!token || !calendarOfferPending(userId)) return false;
  try {
    return !(await answeredOnServer(queryClient, token, CALENDAR_OFFER_GUIDE));
  } catch {
    // Unknown on the server: this device's answer decides.
    return true;
  }
}

export function saveCalendarOfferAnswer(queryClient: QueryClient, token: string | null, userId: string, choice: "apple" | "google" | "no") {
  rememberCalendarOffer(userId, choice);
  saveAnswer(queryClient, token, CALENDAR_OFFER_GUIDE, choice === "no" ? "dismissed" : "completed");
}

/** Whether the person said «Όχι τώρα» to the SMS question at this box on any device. */
export async function smsAskDeclinedOnServer(queryClient: QueryClient, token: string, slug: string): Promise<boolean> {
  try {
    return await answeredOnServer(queryClient, token, smsAskGuideId(slug));
  } catch {
    return false;
  }
}

export function saveSmsAskDeclined(queryClient: QueryClient, token: string | null | undefined, slug: string) {
  saveAnswer(queryClient, token ?? null, smsAskGuideId(slug), "dismissed");
}
