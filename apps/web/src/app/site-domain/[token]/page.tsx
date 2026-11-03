import type { Metadata } from "next";

import { DomainStatusPage } from "@/components/box-site/DomainStatusPage";

type Props = { params: Promise<{ token: string }> };

export const metadata: Metadata = { robots: { index: false } };

/** ADR-388: the link in «Στείλε τις οδηγίες»; whoever runs the domain sees the records and the status, no account. */
export default async function SiteDomainStatusRoute({ params }: Props) {
  const { token } = await params;
  return <DomainStatusPage token={token} />;
}
