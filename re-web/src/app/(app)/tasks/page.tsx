import { Suspense } from "react";
import { TasksView } from "./tasks-view";

export const metadata = { title: "My Tasks" };

export default function Page() {
  return (
    <Suspense>
      <TasksView />
    </Suspense>
  );
}
