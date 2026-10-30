import { Suspense } from "react";
import { SalesmanDetail } from "./salesman-detail";

export const metadata = { title: "Salesman" };

export default function Page({ params }: PageProps<"/salesmen/[id]">) {
  return (
    <Suspense>
      <Resolved params={params} />
    </Suspense>
  );
}

async function Resolved({ params }: { params: PageProps<"/salesmen/[id]">["params"] }) {
  const { id } = await params;
  return <SalesmanDetail id={decodeURIComponent(id)} />;
}
