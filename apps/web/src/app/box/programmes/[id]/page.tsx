import { AuthGuard } from "@/components/auth-guard";
import { MyProgrammePage } from "@/components/programmes/MyProgrammes";

export const dynamic = "force-dynamic";

/** Box › a training programme the member bought (ADR-371, mockup W8 s6). */
export default async function MyProgrammeRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard>
      <MyProgrammePage id={id} />
    </AuthGuard>
  );
}
