export interface CustomerInvoiceReport {
  refCode: number;
  customerId: number;
  customerName: string;
  invoiceDate: Date;
  dueDate: Date;
  invoiceNo: string;
  refAmount: number;
  pendingAmount: number;
  message: string;
}

export interface CustomerInvoiceReportOptions {
  limit?: number;
  customerId?: number;
}

export interface CustomerInvoiceReportRepository {
  getInvoices(options?: CustomerInvoiceReportOptions): Promise<CustomerInvoiceReport[]>;
}
