import { Paperclip } from "lucide-react";

/** Evidence served through the BFF proxy (GET /api/attachments/:filename needs the session). */
export function AttachmentLink({ path, label = "View attachment" }: { path: string; label?: string }) {
  return (
    <a
      href={`/api/rms/attachments/${encodeURIComponent(path)}`}
      target="_blank"
      rel="noreferrer"
      className="mt-1 inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
    >
      <Paperclip className="size-3" />
      {label}
    </a>
  );
}
