import type { ReactNode } from "react";
import { Inbox } from "lucide-react";

export function EmptyState({ icon, title, hint, action }: { icon?: ReactNode; title: string; hint?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 px-6 py-12 text-center">
      <span className="flex size-11 items-center justify-center rounded-full bg-muted text-muted-foreground [&_svg]:size-5">
        {icon ?? <Inbox />}
      </span>
      <div className="text-sm font-medium">{title}</div>
      {hint && <p className="max-w-sm text-xs text-muted-foreground">{hint}</p>}
      {action}
    </div>
  );
}
