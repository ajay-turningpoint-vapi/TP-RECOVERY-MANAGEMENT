"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { FileText, Loader2, Paperclip, X } from "lucide-react";
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
import { friendlyError, rmsUpload } from "@/lib/api";
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
    } catch (e) {
      // The alert is shown too; keep the form open with the reason inside it.
      setError(friendlyError(e));
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
                <FileField
                  id={`f-${f.name}`}
                  value={values[f.name]}
                  onUploading={setUploading}
                  onError={setError}
                  onChange={(path) => set(f.name, path)}
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

/**
 * Photo / PDF picker: a clear "Choose" button, then a preview of what was
 * picked — the photo itself, or a PDF icon with the file name — with Change
 * and Remove. Uploads straight away (POST /api/attachments) and hands the
 * server's file name back as the field value.
 */
function FileField({
  id,
  value,
  onChange,
  onUploading,
  onError,
}: {
  id: string;
  value: string;
  onChange: (path: string) => void;
  onUploading: (busy: boolean) => void;
  onError: (message: string | null) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [picked, setPicked] = useState<{ name: string; isPdf: boolean; url: string } | null>(null);
  const [busy, setBusy] = useState(false);

  // Free the local preview URL when it changes or the form closes.
  useEffect(() => () => { if (picked) URL.revokeObjectURL(picked.url); }, [picked]);

  const choose = async (file: File | undefined) => {
    if (!file) return;
    const isPdf = file.type === "application/pdf" || /\.pdf$/i.test(file.name);
    setPicked({ name: file.name, isPdf, url: URL.createObjectURL(file) });
    setBusy(true);
    onUploading(true);
    onError(null);
    try {
      onChange(await rmsUpload(file));
    } catch (err) {
      setPicked(null);
      onChange("");
      onError(friendlyError(err));
    } finally {
      setBusy(false);
      onUploading(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  };

  const remove = () => {
    setPicked(null);
    onChange("");
  };

  return (
    <div>
      <input
        ref={inputRef}
        id={id}
        type="file"
        accept="image/*,application/pdf"
        className="sr-only"
        onChange={(e) => choose(e.target.files?.[0])}
      />
      {!picked ? (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-input bg-muted/30 px-4 py-5 text-[15px] font-medium text-muted-foreground transition-colors hover:border-primary hover:text-primary"
        >
          <Paperclip className="size-5" /> Choose photo or PDF
        </button>
      ) : (
        <div className="flex items-center gap-3 rounded-lg border-2 bg-card p-2.5">
          <a href={picked.url} target="_blank" rel="noreferrer" className="shrink-0" title="Open">
            {picked.isPdf ? (
              <span className="flex size-16 flex-col items-center justify-center rounded-md bg-red-50 text-red-700 dark:bg-red-500/15 dark:text-red-300">
                <FileText className="size-7" />
                <span className="text-[11px] font-bold">PDF</span>
              </span>
            ) : (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={picked.url} alt="" className="size-16 rounded-md border object-cover" />
            )}
          </a>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold">{picked.name}</div>
            <div className="text-sm text-muted-foreground">
              {busy ? (
                <span className="inline-flex items-center gap-1.5"><Loader2 className="size-3.5 animate-spin" /> Uploading…</span>
              ) : value ? (
                <span className="text-green-700 dark:text-green-300">Attached</span>
              ) : null}
            </div>
          </div>
          <div className="flex shrink-0 gap-1.5">
            <Button type="button" variant="outline" size="sm" disabled={busy} onClick={() => inputRef.current?.click()}>
              Change
            </Button>
            <Button type="button" variant="ghost" size="sm" disabled={busy} onClick={remove} aria-label="Remove file">
              <X />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
