"use client";

import { useState } from "react";
import { Download, ExternalLink, FileText, ImageOff, Loader2, ZoomIn } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

/** Server stores uploads as <uuid>.<ext> — jpg/png/webp photos or pdf. */
const kindOf = (path: string) => (/\.pdf$/i.test(path) ? "pdf" : /\.(jpe?g|png|webp|gif)$/i.test(path) ? "image" : "file");
const fileUrl = (path: string, inline = false) => `/api/rms/attachments/${encodeURIComponent(path)}${inline ? "?inline=1" : ""}`;

/**
 * Attachment preview: a photo shows as a thumbnail, a PDF as a document
 * card. Clicking either opens it large inside the page, with "Open in new
 * tab" and "Download" buttons. Used for every attachment in the app.
 */
export function AttachmentLink({ path, label, size = "md" }: { path: string; label?: string; size?: "sm" | "md" }) {
  const [open, setOpen] = useState(false);
  const [broken, setBroken] = useState(false);
  const kind = kindOf(path);
  const title = label ?? (kind === "pdf" ? "PDF document" : kind === "image" ? "Photo" : "Attached file");
  const small = size === "sm";

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          "group mt-2 inline-flex items-center gap-3 rounded-xl border-2 bg-card p-2 pr-4 text-left transition-colors hover:border-primary hover:bg-accent/40",
          small && "mt-0 gap-2 p-1 pr-3",
        )}
        aria-label={`Open ${title}`}
      >
        <span
          className={cn(
            "relative flex shrink-0 items-center justify-center overflow-hidden rounded-lg bg-muted",
            small ? "size-10" : "h-20 w-24",
          )}
        >
          {kind === "image" && !broken ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={fileUrl(path)} alt="" loading="lazy" onError={() => setBroken(true)} className="size-full object-cover" />
          ) : kind === "pdf" ? (
            <span className="flex flex-col items-center text-red-700 dark:text-red-300">
              <FileText className={small ? "size-5" : "size-8"} />
              {!small && <span className="text-xs font-bold">PDF</span>}
            </span>
          ) : (
            <ImageOff className="size-6 text-muted-foreground" />
          )}
          {kind === "image" && !broken && (
            <span className="absolute inset-0 flex items-center justify-center bg-black/0 text-white opacity-0 transition-all group-hover:bg-black/30 group-hover:opacity-100">
              <ZoomIn className="size-5" />
            </span>
          )}
        </span>
        <span className="min-w-0">
          <span className={cn("block font-semibold", small ? "text-sm" : "text-[15px]")}>{title}</span>
          {!small && <span className="block text-sm text-primary">Click to open</span>}
        </span>
      </button>

      <AttachmentViewer path={path} title={title} open={open} onOpenChange={setOpen} />
    </>
  );
}

function AttachmentViewer({ path, title, open, onOpenChange }: { path: string; title: string; open: boolean; onOpenChange: (o: boolean) => void }) {
  const kind = kindOf(path);
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        onOpenChange(o);
        if (!o) {
          setLoaded(false);
          setFailed(false);
        }
      }}
    >
      <DialogContent className="flex max-h-[92vh] w-[min(1100px,96vw)] max-w-none flex-col gap-4 sm:max-w-none">
        <DialogHeader>
          <DialogTitle className="text-lg">{title}</DialogTitle>
          <DialogDescription>{kind === "pdf" ? "PDF document" : kind === "image" ? "Photo" : "File"}</DialogDescription>
        </DialogHeader>

        <div className="relative flex min-h-[50vh] flex-1 items-center justify-center overflow-auto rounded-xl border-2 bg-muted/50">
          {!loaded && !failed && kind !== "file" && (
            <div className="absolute inset-0 flex items-center justify-center gap-2 text-[15px] text-muted-foreground">
              <Loader2 className="size-5 animate-spin" /> Opening…
            </div>
          )}
          {failed || kind === "file" ? (
            <div className="p-10 text-center text-[15px]">
              <p className="font-semibold">This file cannot be shown here.</p>
              <p className="mt-1 text-muted-foreground">Use “Download” below to save it, or try “Open in new tab”.</p>
            </div>
          ) : kind === "image" ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={fileUrl(path)}
              alt={title}
              onLoad={() => setLoaded(true)}
              onError={() => setFailed(true)}
              className="max-h-[70vh] w-auto max-w-full object-contain"
            />
          ) : (
            <iframe
              src={fileUrl(path, true)}
              title={title}
              onLoad={() => setLoaded(true)}
              className="h-[70vh] w-full rounded-lg bg-white"
            />
          )}
        </div>

        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="outline" render={<a href={fileUrl(path, true)} target="_blank" rel="noreferrer" />}>
            <ExternalLink /> Open in new tab
          </Button>
          <Button variant="outline" render={<a href={fileUrl(path)} download />}>
            <Download /> Download
          </Button>
          <Button onClick={() => onOpenChange(false)}>Close</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
