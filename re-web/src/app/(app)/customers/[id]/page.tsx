import { Customer360 } from "./customer-360";

export const metadata = { title: "Customer 360" };

export default async function Page({ params }: PageProps<"/customers/[id]">) {
  const { id } = await params;
  return <Customer360 id={decodeURIComponent(id)} />;
}
