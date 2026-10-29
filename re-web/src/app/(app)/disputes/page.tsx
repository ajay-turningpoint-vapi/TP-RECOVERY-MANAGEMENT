import { Suspense } from "react";
import { DisputesView } from "./disputes-view";

export const metadata = { title: "Disputes" };

export default function Page() {
  return (
    <Suspense>
      <DisputesView />
    </Suspense>
  );
}
