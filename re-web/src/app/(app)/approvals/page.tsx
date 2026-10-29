import { Suspense } from "react";
import { ApprovalsView } from "./approvals-view";

export const metadata = { title: "Approval Inbox" };

export default function Page() {
  return (
    <Suspense>
      <ApprovalsView />
    </Suspense>
  );
}
