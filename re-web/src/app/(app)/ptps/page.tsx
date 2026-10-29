import { Suspense } from "react";
import { PtpsView } from "./ptps-view";

export const metadata = { title: "Promises to Pay" };

export default function Page() {
  return (
    <Suspense>
      <PtpsView />
    </Suspense>
  );
}
