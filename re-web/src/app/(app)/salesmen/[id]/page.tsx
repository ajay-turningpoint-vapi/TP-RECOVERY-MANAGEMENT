import { SalesmanDetail } from "./salesman-detail";

export const metadata = { title: "Salesman" };

export default async function Page({ params }: PageProps<"/salesmen/[id]">) {
  const { id } = await params;
  return <SalesmanDetail id={decodeURIComponent(id)} />;
}
