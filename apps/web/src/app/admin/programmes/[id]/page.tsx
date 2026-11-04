import { ProgrammeEditor } from "@/components/admin/programmes/ProgrammeEditor";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default async function AdminProgrammeRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["admin"]}>
      <ProgrammeEditor id={id} />
    </AuthGuard>
  );
}
