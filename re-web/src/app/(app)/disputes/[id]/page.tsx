import { DisputeDetail } from "./dispute-detail";

export const metadata = { title: "Dispute" };

export default async function Page({ params }: PageProps<"/disputes/[id]">) {
  const { id } = await params;
  return <DisputeDetail id={id} />;
}
