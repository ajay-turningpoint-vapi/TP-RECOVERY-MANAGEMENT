import fs from 'fs';
import path from 'path';
import sql from 'mssql';
import mssqlDb from '../../config/mssql';
import {
  CustomerInvoiceReport,
  CustomerInvoiceReportOptions,
  CustomerInvoiceReportRepository,
} from './invoiceReport.types';

const QUERY_PATH = path.resolve(__dirname, 'invoiceReport.mssql.sql');

function mapRow(raw: any): CustomerInvoiceReport {
  return {
    refCode: raw.ref_code,
    customerId: raw.customer_id,
    customerName: raw.customer_name,
    invoiceDate: raw.invoice_date,
    dueDate: raw.due_date,
    invoiceNo: raw.invoice_no,
    refAmount: raw.ref_amount ?? 0,
    pendingAmount: raw.pending_amount ?? 0,
    message: raw.message ?? '',
  };
}

export class MssqlInvoiceReportRepository implements CustomerInvoiceReportRepository {
  async getInvoices(options?: CustomerInvoiceReportOptions): Promise<CustomerInvoiceReport[]> {
    if (!mssqlDb.isConnected) {
      await mssqlDb.connect();
    }

    let queryText = fs.readFileSync(QUERY_PATH, 'utf8');

    if (options?.limit) {
      queryText = queryText.replace(/^SELECT\b/m, `SELECT TOP (${Number(options.limit)})`);
    }

    const request = mssqlDb.getPool().request();
    if (options?.customerId != null) {
      request.input('customerId', sql.Int, options.customerId);
      queryText = queryText.replace('/*{{CUSTOMER_FILTER}}*/', 'AND M.Code = @customerId');
    } else {
      queryText = queryText.replace('/*{{CUSTOMER_FILTER}}*/', '');
    }

    const result = await request.query(queryText);
    return result.recordset.map(mapRow);
  }
}
