import { notFound } from "next/navigation";
import { REPORTS } from "../catalog";
import { ReportView } from "./report-view";

export async function generateMetadata({ params }: PageProps<"/reports/[slug]">) {
  const { slug } = await params;
  return { title: REPORTS.find((r) => r.slug === slug)?.title ?? "Report" };
}

export default async function Page({ params }: PageProps<"/reports/[slug]">) {
  const { slug } = await params;
  const report = REPORTS.find((r) => r.slug === slug);
  if (!report) notFound();
  return <ReportView slug={report.slug} />;
}
