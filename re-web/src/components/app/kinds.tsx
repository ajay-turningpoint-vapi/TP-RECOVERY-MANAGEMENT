import { CalendarX2, ClipboardCheck, FileWarning, MapPin, ReceiptText, Repeat2, TrendingDown } from "lucide-react";
import type { TaskKind } from "@/lib/selectors";
import type { Hue } from "./visual";

/** Colour + icon per RE queue item kind — shared by My Tasks, Approvals and the detail panel. */
export const KIND_HUE: Record<TaskKind, Hue> = {
  realTask: "indigo",
  visitReview: "violet",
  overdueTarget: "amber",
  dispute: "violet",
  ptpCorrection: "sky",
  ptpMissed: "rose",
  paymentClaim: "emerald",
};

export const KIND_ICON: Record<TaskKind, React.ReactNode> = {
  realTask: <ClipboardCheck />,
  visitReview: <MapPin />,
  overdueTarget: <TrendingDown />,
  dispute: <FileWarning />,
  ptpCorrection: <Repeat2 />,
  ptpMissed: <CalendarX2 />,
  paymentClaim: <ReceiptText />,
};

