"use client";

import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { DisputePanel } from "@/components/app/dispute-panel";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useRms } from "@/lib/queries";

export function DisputeDetail({ id }: { id: string }) {
  const rms = useRms();
  const d = rms.disputes.find((x) => x.id === id);
  return (
    <div className="mx-auto max-w-[1500px] space-y-4">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" render={<Link href="/disputes" />}>
        <ArrowLeft /> Disputes
      </Button>
      {d ? (
        <DisputePanel dispute={d} rms={rms} />
      ) : rms.isLoading ? (
        <Skeleton className="h-96 w-full" />
      ) : (
        <p className="py-20 text-center text-muted-foreground">Dispute not found (it may be outside the selected branch).</p>
      )}
    </div>
  );
}
