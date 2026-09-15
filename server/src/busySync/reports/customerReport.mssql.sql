/*
 * Canonical customer ledger report against BUSY (MSSQL) — the production
 * query backing MssqlCustomerReportRepository. This is the fuller query
 * supplied directly by the business: it re-adds OPENING_OUTSTANDING,
 * CURRENT_YEAR_INVOICE_AMOUNT / SALES_RETURN / RECEIPTS, LAST_INVOICE_DATE /
 * AMOUNT, EMAIL, OUTSTANDING_STATUS and AS_OF_DATE, and revises some of the
 * balance math (every due / ageing bucket now nets VCHTYPE 14,3,16, and
 * the outer filter drops rows with LEDGER_CLOSING_BALANCE <= 1). Those
 * extra columns are returned but NOT consumed — mssqlCustomerReportRepository
 * mapRow() still reads only the ledger / ageing / contact / salesman /
 * credit fields.
 *
 * Three deliberate deviations from the supplied query are retained, all
 * proven necessary against this exact BUSY data (not speculative):
 *  1. TRY_CONVERT(INT, ...) around A.OF2 / M.I2 and TRY_CONVERT(DECIMAL, ...)
 *     around M.D1 — these columns are declared numeric-ish but contain
 *     stray text (e.g. 'INCENTIVE') in some rows; without the guard the
 *     whole query throws "Conversion failed... to data type int" (hit
 *     this for real, twice, on live data).
 *  2. The PARENTGRP_FILTER placeholder comment inside the inner derived
 *     table's WHERE (after "M.MASTERTYPE = 2") —
 *     mssqlCustomerReportRepository does a literal string replace on it to
 *     inject "AND M.PARENTGRP IN ('code', ...)" for the branch being
 *     synced (config/branches.js). Values are kept quoted — the column
 *     compares as text here; bare ints risk an implicit-conversion error.
 *     If the placeholder is missing, the pull silently spans every
 *     PARENTGRP (all branches at once). It must appear exactly once.
 *  3. The SALESMAN_FILTER placeholder comment after "X.BALANCE_TYPE = 'DR'"
 *     (see the WHERE clause near the end of this file) —
 *     mssqlCustomerReportRepository does a literal string replace on it to
 *     inject "AND X.salesmancode = @salesmanCode" / "AND X.CUSTOMER_ID =
 *     @customerId". If it is missing, per-salesman scoping silently becomes
 *     a no-op (a salesman could fetch any customer). It must appear exactly
 *     once in this file, so it is not written literally here.
 *
 * mssqlCustomerReportRepository injects "TOP (n)" into this query's own
 * leading SELECT when options.limit is set (the trailing ORDER BY makes
 * the outer-wrap form invalid T-SQL).
 */
SELECT
    X.CUSTOMER_ID,
    X.CUSTOMER_NAME,

    X.OPENING_OUTSTANDING,
    X.CURRENT_YEAR_INVOICE_AMOUNT,
    X.CURRENT_YEAR_SALES_RETURN,
    X.CURRENT_YEAR_RECEIPTS,

    X.LEDGER_CLOSING_BALANCE,
    X.BALANCE_TYPE,

    X.AMOUNT_ALREADY_DUE,
    X.FUTURE_DUE_AMOUNT,

    X.AGE_0_30,
    X.AGE_31_60,
    X.AGE_61_90,
    X.AGE_90_PLUS,

    X.MAX_DAYS_OVERDUE,

    CASE
        WHEN X.LEDGER_CLOSING_BALANCE > 0
        THEN 'OUTSTANDING'
        ELSE 'SETTLED'
    END AS OUTSTANDING_STATUS,

    X.LAST_INVOICE_DATE,
    X.LAST_INVOICE_AMOUNT,
    X.LAST_RECEIPT_DATE,
    X.LAST_RECEIPT_AMOUNT,

    X.MOBILE,
    X.EMAIL,
    X.GSTNO,
    X.ADDRESS,
    X.SALESMAN,
    X.salesmancode,
    X.CREDIT_DAYS,
    X.CREDIT_LIMIT,

    CAST(GETDATE() AS DATE) AS AS_OF_DATE

FROM
(
    SELECT

        M.CODE AS CUSTOMER_ID,
        M.NAME AS CUSTOMER_NAME,

        /* =========================================
           OPENING OUTSTANDING
           ========================================= */

        CASE
            WHEN ISNULL(F.D1,0) < 0
            THEN ABS(ISNULL(F.D1,0))
            ELSE 0
        END AS OPENING_OUTSTANDING,


        /* =========================================
           CURRENT YEAR SALES
           ========================================= */

        ISNULL(
            (
                SELECT SUM(ABS(ISNULL(T.VALUE1,0)))
                FROM TRAN3 T
                WHERE
                    T.MASTERCODE1 = M.CODE
                    AND T.VCHTYPE = 9
                    AND T.TYPE = 1
                    AND T.STATUS IN (1,2)
            ),0
        ) AS CURRENT_YEAR_INVOICE_AMOUNT,


        /* =========================================
           CURRENT YEAR SALES RETURN
           ========================================= */

        ISNULL(
            (
                SELECT SUM(ABS(ISNULL(T.VALUE1,0)))
                FROM TRAN3 T
                WHERE
                    T.MASTERCODE1 = M.CODE
                    AND T.VCHTYPE = 3
                    AND T.TYPE = 2
                    AND T.STATUS = 1
                    AND T.METHOD = 2
            ),0
        ) AS CURRENT_YEAR_SALES_RETURN,


        /* =========================================
           CURRENT YEAR RECEIPTS
           ========================================= */

        ISNULL(
            (
                SELECT SUM(ABS(ISNULL(T.VALUE1,0)))
                FROM TRAN3 T
                WHERE
                    T.MASTERCODE1 = M.CODE
                    AND T.VCHTYPE = 14
                    AND T.TYPE = 2
                    AND T.STATUS = 1
                    AND T.METHOD = 2
            ),0
        ) AS CURRENT_YEAR_RECEIPTS,


        /* =========================================
           LEDGER CLOSING BALANCE
           ========================================= */

        ABS(
            ISNULL(F.D1,0)
            +
            (
                ISNULL(F.D23,0) +
                ISNULL(F.D24,0) +
                ISNULL(F.D25,0) +
                ISNULL(F.D26,0) +
                ISNULL(F.D27,0) +
                ISNULL(F.D28,0) +
                ISNULL(F.D29,0) +
                ISNULL(F.D30,0) +
                ISNULL(F.D31,0) +
                ISNULL(F.D32,0) +
                ISNULL(F.D33,0) +
                ISNULL(F.D34,0)
            )
            -
            (
                ISNULL(F.D11,0) +
                ISNULL(F.D12,0) +
                ISNULL(F.D13,0) +
                ISNULL(F.D14,0) +
                ISNULL(F.D15,0) +
                ISNULL(F.D16,0) +
                ISNULL(F.D17,0) +
                ISNULL(F.D18,0) +
                ISNULL(F.D19,0) +
                ISNULL(F.D20,0) +
                ISNULL(F.D21,0) +
                ISNULL(F.D22,0)
            )
        ) AS LEDGER_CLOSING_BALANCE,


        /* =========================================
           BALANCE TYPE
           ========================================= */

        CASE

            WHEN
            (
                ISNULL(F.D1,0)
                +
                ISNULL(F.D23,0) +
                ISNULL(F.D24,0) +
                ISNULL(F.D25,0) +
                ISNULL(F.D26,0) +
                ISNULL(F.D27,0) +
                ISNULL(F.D28,0) +
                ISNULL(F.D29,0) +
                ISNULL(F.D30,0) +
                ISNULL(F.D31,0) +
                ISNULL(F.D32,0) +
                ISNULL(F.D33,0) +
                ISNULL(F.D34,0)
                -
                ISNULL(F.D11,0) -
                ISNULL(F.D12,0) -
                ISNULL(F.D13,0) -
                ISNULL(F.D14,0) -
                ISNULL(F.D15,0) -
                ISNULL(F.D16,0) -
                ISNULL(F.D17,0) -
                ISNULL(F.D18,0) -
                ISNULL(F.D19,0) -
                ISNULL(F.D20,0) -
                ISNULL(F.D21,0) -
                ISNULL(F.D22,0)
            ) < 0
            THEN 'DR'

            WHEN
            (
                ISNULL(F.D1,0)
                +
                ISNULL(F.D23,0) +
                ISNULL(F.D24,0) +
                ISNULL(F.D25,0) +
                ISNULL(F.D26,0) +
                ISNULL(F.D27,0) +
                ISNULL(F.D28,0) +
                ISNULL(F.D29,0) +
                ISNULL(F.D30,0) +
                ISNULL(F.D31,0) +
                ISNULL(F.D32,0) +
                ISNULL(F.D33,0) +
                ISNULL(F.D34,0)
                -
                ISNULL(F.D11,0) -
                ISNULL(F.D12,0) -
                ISNULL(F.D13,0) -
                ISNULL(F.D14,0) -
                ISNULL(F.D15,0) -
                ISNULL(F.D16,0) -
                ISNULL(F.D17,0) -
                ISNULL(F.D18,0) -
                ISNULL(F.D19,0) -
                ISNULL(F.D20,0) -
                ISNULL(F.D21,0) -
                ISNULL(F.D22,0)
            ) > 0
            THEN 'CR'

            ELSE 'ZERO'

        END AS BALANCE_TYPE,


        /* =========================================
           AMOUNT ALREADY DUE
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    CASE
                        WHEN
                            ABS(ISNULL(I.VALUE1,0))
                            -
                            ISNULL(
                            (
                                SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                FROM TRAN3 P
                                WHERE
                                    P.REFCODE = I.REFCODE
                                    AND P.VCHTYPE IN (14,3,16)
                                    AND P.TYPE = 2
                                    AND P.STATUS = 1
                                    AND P.METHOD = 2
                            ),0
                            ) > 0

                        THEN
                            ABS(ISNULL(I.VALUE1,0))
                            -
                            ISNULL(
                            (
                                SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                FROM TRAN3 P
                                WHERE
                                    P.REFCODE = I.REFCODE
                                    AND P.VCHTYPE IN (14,3,16)
                                    AND P.TYPE = 2
                                    AND P.STATUS = 1
                                    AND P.METHOD = 2
                            ),0
                            )

                        ELSE 0
                    END AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()

        ),0) AS AMOUNT_ALREADY_DUE,


        /* =========================================
           FUTURE DUE AMOUNT
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    CASE
                        WHEN
                            ABS(ISNULL(I.VALUE1,0))
                            -
                            ISNULL(
                            (
                                SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                FROM TRAN3 P
                                WHERE
                                    P.REFCODE = I.REFCODE
                                    AND P.VCHTYPE IN (14,3,16)
                                    AND P.TYPE = 2
                                    AND P.STATUS = 1
                                    AND P.METHOD = 2
                            ),0
                            ) > 0

                        THEN
                            ABS(ISNULL(I.VALUE1,0))
                            -
                            ISNULL(
                            (
                                SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                FROM TRAN3 P
                                WHERE
                                    P.REFCODE = I.REFCODE
                                    AND P.VCHTYPE IN (14,3,16)
                                    AND P.TYPE = 2
                                    AND P.STATUS = 1
                                    AND P.METHOD = 2
                            ),0
                            )

                        ELSE 0
                    END AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE > GETDATE()

        ),0) AS FUTURE_DUE_AMOUNT,


        /* =========================================
           0 - 30 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    ABS(ISNULL(I.VALUE1,0))
                    -
                    ISNULL(
                    (
                        SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                        FROM TRAN3 P
                        WHERE
                            P.REFCODE = I.REFCODE
                            AND P.VCHTYPE IN (14,3,16)
                            AND P.TYPE = 2
                            AND P.STATUS = 1
                            AND P.METHOD = 2
                    ),0) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 0 AND 30

        ),0) AS AGE_0_30,


        /* =========================================
           31 - 60 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    ABS(ISNULL(I.VALUE1,0))
                    -
                    ISNULL(
                    (
                        SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                        FROM TRAN3 P
                        WHERE
                            P.REFCODE = I.REFCODE
                            AND P.VCHTYPE IN (14,3,16)
                            AND P.TYPE = 2
                            AND P.STATUS = 1
                            AND P.METHOD = 2
                    ),0) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 31 AND 60

        ),0) AS AGE_31_60,


        /* =========================================
           61 - 90 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    ABS(ISNULL(I.VALUE1,0))
                    -
                    ISNULL(
                    (
                        SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                        FROM TRAN3 P
                        WHERE
                            P.REFCODE = I.REFCODE
                            AND P.VCHTYPE IN (14,3,16)
                            AND P.TYPE = 2
                            AND P.STATUS = 1
                            AND P.METHOD = 2
                    ),0) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 61 AND 90

        ),0) AS AGE_61_90,


        /* =========================================
           90+ DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    ABS(ISNULL(I.VALUE1,0))
                    -
                    ISNULL(
                    (
                        SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                        FROM TRAN3 P
                        WHERE
                            P.REFCODE = I.REFCODE
                            AND P.VCHTYPE IN (14,3,16)
                            AND P.TYPE = 2
                            AND P.STATUS = 1
                            AND P.METHOD = 2
                    ),0) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) > 90

        ),0) AS AGE_90_PLUS,


        /* =========================================
           MAX DAYS OVERDUE
           ========================================= */

        ISNULL(
        (
            SELECT MAX(DATEDIFF(DAY,Q.DUEDATE,GETDATE()))
            FROM
            (
                SELECT
                    I.REFCODE,

                    ABS(ISNULL(I.VALUE1,0))
                    -
                    ISNULL(
                    (
                        SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                        FROM TRAN3 P
                        WHERE
                            P.REFCODE = I.REFCODE
                            AND P.VCHTYPE IN (14,3,16)
                            AND P.TYPE = 2
                            AND P.STATUS = 1
                            AND P.METHOD = 2
                    ),0) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()

        ),0) AS MAX_DAYS_OVERDUE,


        /* =========================================
           LAST INVOICE DATE & AMOUNT
           ========================================= */

        (
            SELECT TOP 1 T.[Date]
            FROM TRAN3 T
            WHERE
                T.MASTERCODE1 = M.CODE
                AND T.VCHTYPE = 9
                AND T.TYPE = 1
                AND T.STATUS IN (1,2)
            ORDER BY T.[Date] DESC, T.VchCode DESC
        ) AS LAST_INVOICE_DATE,

        (
            SELECT SUM(ABS(ISNULL(T2.VALUE1,0)))
            FROM TRAN3 T2
            WHERE
                T2.MASTERCODE1 = M.CODE
                AND T2.VCHTYPE = 9
                AND T2.TYPE = 1
                AND T2.STATUS IN (1,2)
                AND T2.VchCode =
                (
                    SELECT TOP 1 T3.VchCode
                    FROM TRAN3 T3
                    WHERE
                        T3.MASTERCODE1 = M.CODE
                        AND T3.VCHTYPE = 9
                        AND T3.TYPE = 1
                        AND T3.STATUS IN (1,2)
                    ORDER BY T3.[Date] DESC, T3.VchCode DESC
                )
        ) AS LAST_INVOICE_AMOUNT,


        /* =========================================
           LAST RECEIPT DATE & AMOUNT
           (payment/receipt vouchers — VCHTYPE=14, TYPE=2, STATUS=1,
           METHOD=2 — matches the CURRENT_YEAR_RECEIPTS subquery's own
           filter exactly. Answers "when did the customer last actually
           pay", distinct from LAST_INVOICE_* above.)
           ========================================= */

        (
            SELECT TOP 1 T.[Date]
            FROM TRAN3 T
            WHERE
                T.MASTERCODE1 = M.CODE
                AND T.VCHTYPE = 14
                AND T.TYPE = 2
                AND T.STATUS = 1
                AND T.METHOD = 2
            ORDER BY T.[Date] DESC, T.VchCode DESC
        ) AS LAST_RECEIPT_DATE,

        (
            SELECT SUM(ABS(ISNULL(T2.VALUE1,0)))
            FROM TRAN3 T2
            WHERE
                T2.MASTERCODE1 = M.CODE
                AND T2.VCHTYPE = 14
                AND T2.TYPE = 2
                AND T2.STATUS = 1
                AND T2.METHOD = 2
                AND T2.VchCode =
                (
                    SELECT TOP 1 T3.VchCode
                    FROM TRAN3 T3
                    WHERE
                        T3.MASTERCODE1 = M.CODE
                        AND T3.VCHTYPE = 14
                        AND T3.TYPE = 2
                        AND T3.STATUS = 1
                        AND T3.METHOD = 2
                    ORDER BY T3.[Date] DESC, T3.VchCode DESC
                )
        ) AS LAST_RECEIPT_AMOUNT,


        /* =========================================
           CUSTOMER DETAILS
           ========================================= */

        ISNULL(A.MOBILE,'') AS MOBILE,
        ISNULL(A.EMAIL,'') AS EMAIL,
        ISNULL(A.GSTNO,'') AS GSTNO,

        ISNULL(A.ADDRESS1,'')
        +
        ISNULL(A.ADDRESS2,'')
        +
        ISNULL(A.ADDRESS3,'')
        +
        ISNULL(A.ADDRESS4,'') AS ADDRESS,


        /* SALESMAN */

        (
            SELECT TOP 1 S.NAME
            FROM MASTER1 S
            WHERE S.CODE = TRY_CONVERT(INT, A.OF2)
        ) AS SALESMAN,

        TRY_CONVERT(INT, A.OF2) AS salesmancode,

        ISNULL(TRY_CONVERT(INT, M.I2),0) AS CREDIT_DAYS,

        ISNULL(TRY_CONVERT(DECIMAL(18,2), M.D1),0) AS CREDIT_LIMIT


    FROM MASTER1 M

    LEFT JOIN FOLIO1 F
        ON F.MASTERCODE = M.CODE

    LEFT JOIN MASTERADDRESSINFO A
        ON A.MASTERCODE = M.CODE

    WHERE

        M.MASTERTYPE = 2

        /*{{PARENTGRP_FILTER}}*/

) X

/* =========================================
   ONLY DR CUSTOMERS
   ========================================= */

WHERE
    X.BALANCE_TYPE = 'DR'
    AND X.LEDGER_CLOSING_BALANCE > 1
    /*{{SALESMAN_FILTER}}*/

ORDER BY
    X.CUSTOMER_NAME
