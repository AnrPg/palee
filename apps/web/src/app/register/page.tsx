import { GuestLanding } from "@/components/landing/GuestLanding";

export const dynamic = "force-dynamic";

/** Sign up (ADR-555): the guest landing with the form already open. */
export default function RegisterPage() {
  return <GuestLanding initialMode="register" />;
}
