"use client";

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";

export type Option = { value: string; label: string };

/** Thin wrapper over the Base UI select for the common "pick one string" case. */
export function SimpleSelect({
  value,
  onChange,
  options,
  placeholder,
  className,
  size = "default",
  "aria-label": ariaLabel,
}: {
  value: string;
  onChange: (v: string) => void;
  options: Option[] | string[];
  placeholder?: string;
  className?: string;
  size?: "sm" | "default";
  "aria-label"?: string;
}) {
  const items: Option[] = options.map((o) => (typeof o === "string" ? { value: o, label: o } : o));
  return (
    <Select items={items} value={value} onValueChange={(v) => v != null && onChange(String(v))}>
      <SelectTrigger size={size} className={cn("min-w-36", className)} aria-label={ariaLabel}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent alignItemWithTrigger={false} align="start">
        {items.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
