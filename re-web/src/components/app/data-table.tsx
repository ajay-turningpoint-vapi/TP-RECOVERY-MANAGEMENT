"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
  type VisibilityState,
} from "@tanstack/react-table";
import {
  ArrowDown,
  ArrowUp,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  Download,
  Search,
  SearchX,
  CircleAlert,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { downloadCsv } from "@/lib/csv";
import { useRmsData } from "@/lib/queries";
import { EmptyState } from "./empty-state";
import { SimpleSelect } from "./simple-select";

declare module "@tanstack/react-table" {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  interface ColumnMeta<TData, TValue> {
    /** Plain value for CSV export (defaults to the accessor value). */
    csv?: (row: TData) => string | number | null | undefined;
    align?: "right" | "center";
    className?: string;
  }
}

export function DataTable<T>({
  columns,
  data,
  loading,
  searchPlaceholder = "Search…",
  searchText,
  onRowClick,
  toolbar,
  exportName,
  initialSorting = [],
  initialHidden = {},
  pageSize = 25,
  emptyText = "Nothing to show.",
  rowClassName,
}: {
  columns: ColumnDef<T, unknown>[];
  data: T[];
  loading?: boolean;
  searchPlaceholder?: string;
  /** Text a row is matched against for the search box. Omit to hide search. */
  searchText?: (row: T) => string;
  onRowClick?: (row: T) => void;
  toolbar?: ReactNode;
  exportName?: string;
  initialSorting?: SortingState;
  initialHidden?: VisibilityState;
  pageSize?: number;
  emptyText?: string;
  rowClassName?: (row: T) => string | undefined;
  dense?: boolean;
}) {
  const [sorting, setSorting] = useState<SortingState>(initialSorting);
  const [visibility, setVisibility] = useState<VisibilityState>(initialHidden);
  const [query, setQuery] = useState("");
  const searchRef = useRef<HTMLInputElement>(null);
  const { loadFailed } = useRmsData();

  // "/" jumps to this table's search box (ignored while typing elsewhere).
  useEffect(() => {
    if (!searchText) return;
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement | null;
      if (e.key !== "/" || e.metaKey || e.ctrlKey || el?.closest("input, textarea, select, [contenteditable=true]")) return;
      e.preventDefault();
      searchRef.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [searchText]);

  const filtered = useMemo(() => {
    if (!searchText || !query.trim()) return data;
    const q = query.trim().toLowerCase();
    return data.filter((r) => searchText(r).toLowerCase().includes(q));
  }, [data, query, searchText]);

  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: filtered,
    columns,
    state: { sorting, columnVisibility: visibility },
    onSortingChange: setSorting,
    onColumnVisibilityChange: setVisibility,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize } },
    autoResetPageIndex: true,
  });

  const exportCsv = () => {
    const cols = table.getVisibleLeafColumns().filter((c) => c.id !== "actions" && c.id !== "select");
    const header = cols.map((c) => (typeof c.columnDef.header === "string" ? c.columnDef.header : c.id));
    const rows = table.getSortedRowModel().rows.map((r) =>
      cols.map((c) => {
        const meta = c.columnDef.meta;
        return meta?.csv ? meta.csv(r.original) : (r.getValue(c.id) as string | number | null);
      }),
    );
    downloadCsv(exportName ?? "export", header, rows);
  };

  const { pageIndex, pageSize: size } = table.getState().pagination;
  const total = table.getFilteredRowModel().rows.length;
  const from = total === 0 ? 0 : pageIndex * size + 1;
  const to = Math.min(total, (pageIndex + 1) * size);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {searchText && (
          <div className="relative w-full sm:w-80">
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-foreground" />
            <Input
              ref={searchRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Escape" && (setQuery(""), e.currentTarget.blur())}
              placeholder={searchPlaceholder}
              className="pl-10"
            />
          </div>
        )}
        {toolbar}
        <div className="ml-auto flex items-center gap-2">
          {exportName && (
            <Button variant="outline" onClick={exportCsv} disabled={!total}>
              <Download />
              Download (Excel)
            </Button>
          )}
        </div>
      </div>

      <div className="overflow-hidden rounded-xl border-2 bg-card">
        <div className="max-h-[70vh] overflow-auto">
          <Table>
            <TableHeader className="sticky top-0 z-10 bg-muted">
              {table.getHeaderGroups().map((hg) => (
                <TableRow key={hg.id} className="hover:bg-transparent">
                  {hg.headers.map((h) => {
                    const sorted = h.column.getIsSorted();
                    const align = h.column.columnDef.meta?.align;
                    return (
                      <TableHead
                        key={h.id}
                        className={cn(
                          "h-11 text-[15px] font-semibold whitespace-nowrap text-foreground",
                          align === "right" && "text-right",
                          align === "center" && "text-center",
                          h.column.columnDef.meta?.className,
                        )}
                      >
                        {h.isPlaceholder ? null : h.column.getCanSort() ? (
                          <button
                            type="button"
                            onClick={h.column.getToggleSortingHandler()}
                            className={cn(
                              "inline-flex items-center gap-1 hover:text-foreground",
                              align === "right" && "flex-row-reverse",
                            )}
                          >
                            {flexRender(h.column.columnDef.header, h.getContext())}
                            {sorted === "asc" ? (
                              <ArrowUp className="size-3" />
                            ) : sorted === "desc" ? (
                              <ArrowDown className="size-3" />
                            ) : (
                              <ChevronsUpDown className="size-3 opacity-40" />
                            )}
                          </button>
                        ) : (
                          flexRender(h.column.columnDef.header, h.getContext())
                        )}
                      </TableHead>
                    );
                  })}
                  {onRowClick && <TableHead className="w-28" />}
                </TableRow>
              ))}
            </TableHeader>
            <TableBody>
              {loading ? (
                Array.from({ length: 8 }).map((_, i) => (
                  <TableRow key={i}>
                    {table.getVisibleLeafColumns().map((c) => (
                      <TableCell key={c.id} className="py-3">
                        <Skeleton className="h-4 w-full max-w-32" style={{ animationDelay: `${i * 60}ms` }} />
                      </TableCell>
                    ))}
                    {onRowClick && <TableCell />}
                  </TableRow>
                ))
              ) : table.getRowModel().rows.length === 0 ? (
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={table.getVisibleLeafColumns().length + (onRowClick ? 1 : 0)} className="p-0">
                    {loadFailed ? (
                      <EmptyState icon={<CircleAlert />} title="Could not load this list" hint="See the red message at the top of the page and press Try again." />
                    ) : (
                      <EmptyState
                        icon={query ? <SearchX /> : undefined}
                        title={query ? `No matches for “${query}”` : emptyText}
                        hint={query ? "Try a different name, code or salesman." : undefined}
                      />
                    )}
                  </TableCell>
                </TableRow>
              ) : (
                table.getRowModel().rows.map((row) => (
                  <TableRow
                    key={row.id}
                    onClick={onRowClick ? () => onRowClick(row.original) : undefined}
                    onKeyDown={
                      onRowClick
                        ? (e) => {
                            if (e.key === "Enter" || e.key === " ") {
                              e.preventDefault();
                              onRowClick(row.original);
                            }
                          }
                        : undefined
                    }
                    tabIndex={onRowClick ? 0 : undefined}
                    className={cn(
                      "group/row border-b-2 transition-colors hover:bg-accent/60",
                      onRowClick && "cursor-pointer focus-visible:bg-accent/50 focus-visible:outline-none",
                      rowClassName?.(row.original),
                    )}
                  >
                    {row.getVisibleCells().map((cell) => {
                      const align = cell.column.columnDef.meta?.align;
                      return (
                        <TableCell
                          key={cell.id}
                          className={cn(
                            "py-3",
                            align === "right" && "tabular text-right",
                            align === "center" && "text-center",
                            cell.column.columnDef.meta?.className,
                          )}
                        >
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </TableCell>
                      );
                    })}
                    {onRowClick && (
                      <TableCell className="w-28 pr-4 text-right">
                        <span className="inline-flex h-9 items-center gap-1 rounded-lg border-2 border-primary/40 px-3 text-sm font-semibold text-primary group-hover/row:bg-primary group-hover/row:text-primary-foreground">
                          Open <ChevronRight className="size-4" />
                        </span>
                      </TableCell>
                    )}
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 text-sm text-muted-foreground">
        <span className="tabular">
          {total === 0 ? "Nothing to show" : `Showing ${from} to ${to} of ${total.toLocaleString("en-IN")}`}
          {data.length !== total && ` (filtered from ${data.length.toLocaleString("en-IN")})`}
        </span>
        <div className="flex items-center gap-1">
          <SimpleSelect
            value={String(size)}
            onChange={(v) => table.setPageSize(Number(v))}
            options={["10", "25", "50", "100"].map((n) => ({ value: n, label: `Show ${n}` }))}
            className="mr-2 min-w-28"
            aria-label="Rows per page"
          />
          <Button variant="outline" onClick={() => table.previousPage()} disabled={!table.getCanPreviousPage()}>
            <ChevronLeft /> Previous
          </Button>
          <span className="tabular px-2">
            Page {pageIndex + 1} of {Math.max(1, table.getPageCount())}
          </span>
          <Button variant="outline" onClick={() => table.nextPage()} disabled={!table.getCanNextPage()}>
            Next <ChevronRight />
          </Button>
        </div>
      </div>
    </div>
  );
}
