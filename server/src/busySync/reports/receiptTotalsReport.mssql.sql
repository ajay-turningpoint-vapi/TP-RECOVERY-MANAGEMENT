-- Per-customer payment totals over a date range, used by PTP verification
-- (services/ptpVerificationService.js) to check whether a customer's
-- promised payment actually landed in BUSY, keyed by the BUSY
-- transaction/payment date — never the date RMS happened to sync/discover
-- the receipt (BUSY entry lags real payments by ~1.5 days; see the PTP
-- verification service's doc comment for the full business rule).
--
-- Counts both Receipt (VchType 14) and Journal (VchType 16) vouchers as a
-- valid payment — matches how the separate customer ageing/balance query
-- (customerReport.mssql.sql) already treats these two voucher types when
-- netting a customer's balance. VchType 3 (also used there) is deliberately
-- NOT included here (business confirmed) — it's a different kind of ledger
-- entry (e.g. a return/adjustment), not evidence a promised payment arrived.
--
-- TOTAL_ENTRIES, RECEIPT_AMOUNT, and JOURNAL_AMOUNT are informational only
-- (e.g. for audit/debugging) — the verification decision is made purely on
-- TOTAL_AMOUNT, the combined sum of both voucher types.
SELECT
    M.CODE                          AS CUSTOMER_ID,
    M.NAME                          AS CUSTOMER_NAME,
    COUNT(*)                        AS TOTAL_ENTRIES,

    SUM(
        CASE WHEN T.VchType = 14 THEN ABS(ISNULL(T.Value1,0)) ELSE 0 END
    )                                AS RECEIPT_AMOUNT,

    SUM(
        CASE WHEN T.VchType = 16 THEN ABS(ISNULL(T.Value1,0)) ELSE 0 END
    )                                AS JOURNAL_AMOUNT,

    SUM(ABS(ISNULL(T.Value1,0)))    AS TOTAL_AMOUNT

FROM TRAN2 T

INNER JOIN MASTER1 M
    ON M.CODE = T.MasterCode1
    AND M.MASTERTYPE = 2

WHERE
    T.VchType IN (14,16)
    AND M.PARENTGRP IN
    (
        574140,
        574141,
        258335,
        577533
    )
    AND CONVERT(DATE, T.[Date]) >= @startDate
    AND CONVERT(DATE, T.[Date]) <= @endDate

GROUP BY
    M.CODE,
    M.NAME

ORDER BY
    M.NAME
