import { ProgrammesConsole } from "@/components/admin/programmes/ProgrammesConsole";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminProgrammesPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <ProgrammesConsole />
    </AuthGuard>
  );
}
