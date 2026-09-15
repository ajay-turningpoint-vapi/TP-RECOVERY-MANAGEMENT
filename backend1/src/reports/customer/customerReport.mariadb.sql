-- Canonical customer report, read from the synced BUSY_SOURCE_DATA
-- mirror (MariaDB) rather than live BUSY. Column aliases match
-- CustomerReport (src/reports/customer/customerReport.types.ts) exactly,
-- so the repository can hand the rows straight through with only
-- type/null normalization (no per-column remapping needed).
SELECT
    customer_id                    AS customerId,
    customer_name                  AS customerName,

    ledger_closing_balance         AS ledgerClosingBalance,
    balance_type                   AS balanceType,

    last_invoice_date              AS lastInvoiceDate,
    last_invoice_amount            AS lastInvoiceAmount,

    amount_already_due             AS amountAlreadyDue,
    future_due_amount              AS futureDueAmount,

    age_0_30                       AS age0_30,
    age_31_60                      AS age31_60,
    age_61_90                      AS age61_90,
    age_90_plus                    AS age90Plus,

    max_days_overdue               AS maxDaysOverdue,
    outstanding_status             AS outstandingStatus,

    mobile,
    gstno                          AS gstNo,
    address,

    salesman,
    salesman_code                  AS salesmanCode,

    credit_days                    AS creditDays,
    credit_limit                   AS creditLimit
FROM customer_ageing_snapshot
WHERE 1=1
    /*{{BRANCH_FILTER}}*/
    /*{{SALESMAN_FILTER}}*/
ORDER BY customer_name
