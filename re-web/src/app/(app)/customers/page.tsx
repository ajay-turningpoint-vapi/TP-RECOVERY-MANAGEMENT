import { Suspense } from "react";
import { CustomersView } from "./customers-view";

export const metadata = { title: "Customers" };

export default function Page() {
  return (
    <Suspense>
      <CustomersView />
    </Suspense>
  );
}
