import { PublicProgrammePage } from "@/components/programmes/PublicProgrammePage";

type Props = { params: Promise<{ slug: string; id: string }> };

/** One programme of a box (ADR-370/371, mockup W8 s4/s5): public preview, buying on the web. */
export default async function PublicProgrammeRoute({ params }: Props) {
  const { slug, id } = await params;
  return <PublicProgrammePage slug={slug} id={id} />;
}
