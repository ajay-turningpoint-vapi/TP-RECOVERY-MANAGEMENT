import type { ReactNode } from "react";
import { IconTile, type Hue } from "./visual";

export function PageHeader({
  title,
  description,
  actions,
  eyebrow,
  icon,
  hue = "indigo",
}: {
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  eyebrow?: ReactNode;
  icon?: ReactNode;
  hue?: Hue;
}) {
  return (
    <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex min-w-0 items-center gap-4">
        {icon && (
          <IconTile hue={hue} size="lg">
            {icon}
          </IconTile>
        )}
        <div className="min-w-0 space-y-1">
          {eyebrow && <div className="text-base font-semibold text-muted-foreground">{eyebrow}</div>}
          <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
          {description && <p className="max-w-3xl text-base text-muted-foreground">{description}</p>}
        </div>
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-2">
      <h2 className="text-lg font-semibold tracking-tight">{children}</h2>
      {action}
    </div>
  );
}
