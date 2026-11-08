import { GuestLanding } from "@/components/landing/GuestLanding";

export const dynamic = "force-dynamic";

/** Sign in (ADR-555): the guest landing with the form already open. */
export default function LoginPage() {
  return <GuestLanding initialMode="login" />;
}
