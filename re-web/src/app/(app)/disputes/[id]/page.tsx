import { Suspense } from "react";
import { DisputeDetail } from "./dispute-detail";

export const metadata = { title: "Dispute" };

export default function Page({ params }: PageProps<"/disputes/[id]">) {
  return (
    <Suspense>
      <Resolved params={params} />
    </Suspense>
  );
}

async function Resolved({ params }: { params: PageProps<"/disputes/[id]">["params"] }) {
  const { id } = await params;
  return <DisputeDetail id={id} />;
}
