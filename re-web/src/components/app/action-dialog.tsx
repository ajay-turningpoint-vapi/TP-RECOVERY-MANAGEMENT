"use client";

import { useEffect, useState, type ReactNode } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { rmsUpload } from "@/lib/api";
import { SimpleSelect, type Option } from "./simple-select";

export type Field = {
  name: string;
  label: string;
  type: "text" | "textarea" | "datetime" | "number" | "select" | "file";
  required?: boolean;
  placeholder?: string;
  options?: Option[];
  defaultValue?: string;
  hint?: string;
};

/**
 * One dialog for every RE command that needs input — a reason, a
 * deadline, a new owner. Required fields are enforced before submit; the
 * submit button stays disabled while the request is in flight so a
 * double-click can't fire twice.
 */
export function ActionDialog({
  open,
  onOpenChange,
  title,
  description,
  fields,
  submitLabel = "Confirm",
  destructive,
  onSubmit,
  children,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: string;
  description?: ReactNode;
  fields: Field[];
  submitLabel?: string;
  destructive?: boolean;
  onSubmit: (values: Record<string, string>) => Promise<unknown>;
  children?: ReactNode;
}) {
  const initial = () => Object.fromEntries(fields.map((f) => [f.name, f.defaultValue ?? ""]));
  const [values, setValues] = useState<Record<string, string>>(initial);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    if (open) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setValues(initial());
      setError(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const submit = async () => {
    const missing = fields.find((f) => f.required && !values[f.name]?.trim());
    if (missing) return setError(`${missing.label} is required.`);
    setError(null);
    setPending(true);
    try {
      await onSubmit(values);
      onOpenChange(false);
    } catch {
      /* toast already shown by useRmsAction */
    } finally {
      setPending(false);
    }
  };

  const set = (name: string, v: string) => setValues((s) => ({ ...s, [name]: v }));

  return (
    <Dialog open={open} onOpenChange={(o) => !pending && onOpenChange(o)}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
        <div className="space-y-4">
          {fields.map((f) => (
            <div key={f.name} className="space-y-1.5">
              <Label htmlFor={`f-${f.name}`}>
                {f.label}
                {f.required && <span className="text-destructive">*</span>}
              </Label>
              {f.type === "textarea" ? (
                <Textarea
                  id={`f-${f.name}`}
                  rows={3}
                  placeholder={f.placeholder}
                  value={values[f.name]}
                  onChange={(e) => set(f.name, e.target.value)}
                />
              ) : f.type === "file" ? (
                <Input
                  id={`f-${f.name}`}
                  type="file"
                  accept="image/*,application/pdf"
                  onChange={async (e) => {
                    const file = e.target.files?.[0];
                    if (!file) return set(f.name, "");
                    setUploading(true);
                    setError(null);
                    try {
                      set(f.name, await rmsUpload(file));
                    } catch (err) {
                      set(f.name, "");
                      setError(err instanceof Error ? err.message : "Upload failed");
                    } finally {
                      setUploading(false);
                    }
                  }}
                />
              ) : f.type === "select" ? (
                <SimpleSelect
                  value={values[f.name]}
                  onChange={(v) => set(f.name, v)}
                  options={f.options ?? []}
                  placeholder={f.placeholder ?? "Select…"}
                  className="w-full"
                />
              ) : (
                <Input
                  id={`f-${f.name}`}
                  type={f.type === "datetime" ? "datetime-local" : f.type}
                  placeholder={f.placeholder}
                  value={values[f.name]}
                  onChange={(e) => set(f.name, e.target.value)}
                />
              )}
              {f.hint && <p className="text-xs text-muted-foreground">{f.hint}</p>}
            </div>
          ))}
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button variant={destructive ? "destructive" : "default"} onClick={submit} disabled={pending || uploading}>
            {(pending || uploading) && <Loader2 className="animate-spin" />}
            {uploading ? "Uploading…" : submitLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Small state helper: `const dlg = useDialog<Target>()` → `dlg.open(target)`, `dlg.target`, `dlg.props`. */
export function useDialog<T = true>() {
  const [target, setTarget] = useState<T | null>(null);
  return {
    target,
    open: (t: T) => setTarget(t),
    close: () => setTarget(null),
    props: { open: target != null, onOpenChange: (o: boolean) => !o && setTarget(null) },
  };
}
