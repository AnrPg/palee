import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { SmsUnsubscribePage } from "@/components/channels/SmsUnsubscribePage";

type Props = { params: Promise<{ token: string }> };

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("SmsUnsubscribe");
  return { title: t("metaTitle"), robots: { index: false, follow: false }, referrer: "no-referrer" };
}

/**
 * ADR-390: the short link at the end of a marketing SMS («Διακοπή:
 * palee.app/u/…»). Opening it changes nothing; the person's tap stops offers
 * by SMS from that box. Updates (a class cancelled) keep coming.
 */
export default async function SmsUnsubscribeRoute({ params }: Props) {
  const { token } = await params;
  return <SmsUnsubscribePage token={token} />;
}
