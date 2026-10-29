import { Suspense } from "react";
import { QueueView } from "./queue-view";

export const metadata = { title: "Recovery Queue" };

export default function Page() {
  return (
    <Suspense>
      <QueueView />
    </Suspense>
  );
}
