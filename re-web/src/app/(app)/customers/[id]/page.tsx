import { Suspense } from "react";
import { Customer360 } from "./customer-360";

export const metadata = { title: "Customer 360" };

export default function Page({ params }: PageProps<"/customers/[id]">) {
  return (
    <Suspense>
      <Resolved params={params} />
    </Suspense>
  );
}

async function Resolved({ params }: { params: PageProps<"/customers/[id]">["params"] }) {
  const { id } = await params;
  return <Customer360 id={decodeURIComponent(id)} />;
}
