/*
 * Canonical customer ledger report against BUSY (MSSQL) — the production
 * query backing MssqlCustomerReportRepository. This revision (supplied
 * directly by the business) surfaces AMOUNT_ALREADY_DUE_NET_OF_ADVANCE
 * (instead of the plain AMOUNT_ALREADY_DUE) as the due figure the app
 * actually uses — it nets out any opening credit advance (F.D1 > 0, an
 * unallocated on-account payment/advance) from what's counted as due, so
 * a customer's "due" can no longer exceed what's genuinely still owed.
 * AGE_90_PLUS gets the same advance-netting treatment (previously a plain
 * ISNULL(...) like the other age buckets). Everything else — OPENING_
 * OUTSTANDING/OPENING_CREDIT_ADVANCE, CURRENT_YEAR_*, LEDGER_CLOSING_
 * BALANCE, BALANCE_TYPE, the underlying AMOUNT_ALREADY_DUE (still
 * computed, just not surfaced outer), FUTURE_DUE_AMOUNT, AGE_0_30/31_60/
 * 61_90, MAX_DAYS_OVERDUE, LAST_INVOICE_/LAST_RECEIPT_ fields, contact/
 * salesman/credit fields — is unchanged from the prior revision. Two
 * intermediate columns (OPENING_OUTSTANDING12, AMOUNT_ALREADY_DUE, now
 * effectively superseded by AMOUNT_ALREADY_DUE_NET_OF_ADVANCE) are
 * computed in the inner derived table but not surfaced in the outer
 * SELECT; mssqlCustomerReportRepository's mapRow() only reads the
 * ledger / ageing / contact / salesman / credit fields it always has.
 *
 * Four deliberate deviations from the supplied query are retained, all
 * proven necessary against this exact BUSY data or this codebase's
 * surrounding JS (not speculative):
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
 *  3. The SALESMAN_FILTER placeholder comment after
 *     "X.LEDGER_CLOSING_BALANCE > 1" (see the WHERE clause near the end
 *     of this file) — mssqlCustomerReportRepository does a literal string
 *     replace on it to inject "AND X.salesmancode = @salesmanCode" /
 *     "AND X.CUSTOMER_ID = @customerId". If it is missing, per-salesman
 *     scoping silently becomes a no-op (a salesman could fetch any
 *     customer). It must appear exactly once in this file, so it is not
 *     written literally here.
 *  4. The outer SELECT aliases the salesman-code column back to
 *     lowercase (`X.SALESMANCODE AS salesmancode`) — mssqlCustomerReport
 *     Repository's mapRow() reads `raw.salesmancode` (lowercase); the
 *     mssql driver's recordset keys match the exact SELECT alias casing,
 *     and JS property access is case-sensitive, so without this the
 *     salesman/credit fields would read as undefined for every row.
 *
 * mssqlCustomerReportRepository injects "TOP (n)" into this query's own
 * leading SELECT when options.limit is set (the trailing ORDER BY makes
 * the outer-wrap form invalid T-SQL).
 */
SELECT
    X.CUSTOMER_ID,
    X.CUSTOMER_NAME,

    X.OPENING_OUTSTANDING,
    X.OPENING_CREDIT_ADVANCE,

    X.CURRENT_YEAR_INVOICE_AMOUNT,
    X.CURRENT_YEAR_SALES_RETURN,
    X.CURRENT_YEAR_RECEIPTS,

    X.LEDGER_CLOSING_BALANCE,
    X.BALANCE_TYPE,

    X.AMOUNT_ALREADY_DUE_NET_OF_ADVANCE,
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
    X.SALESMANCODE AS salesmancode,
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
        END AS OPENING_OUTSTANDING12,

        ABS(ISNULL(F.D1,0)) AS OPENING_OUTSTANDING,


        /* =========================================
           OPENING CREDIT ADVANCE
           ========================================= */

        CASE
            WHEN ISNULL(F.D1,0) > 0
            THEN F.D1
            ELSE 0
        END AS OPENING_CREDIT_ADVANCE,


        /* =========================================
           CURRENT YEAR SALES / INVOICE
           VCHTYPE 9
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
        ),0) AS CURRENT_YEAR_INVOICE_AMOUNT,


        /* =========================================
           CURRENT YEAR SALES RETURN
           VCHTYPE 3
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
        ),0) AS CURRENT_YEAR_SALES_RETURN,


        /* =========================================
           CURRENT YEAR RECEIPTS
           VCHTYPE 14
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
        ),0) AS CURRENT_YEAR_RECEIPTS,


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

           INVOICE / DR NOTE
             +
           RECEIPT / SALES RETURN / CR NOTE
             -

           DR NOTE  = VCHTYPE 17
           CR NOTE  = VCHTYPE 18
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    (
                        /* ORIGINAL INVOICE */
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - VCHTYPE 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* RECEIPT + SALES RETURN + OTHER + CR NOTE */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()

        ),0) AS AMOUNT_ALREADY_DUE,


        /* =========================================
           AMOUNT ALREADY DUE NET OF ADVANCE
           ========================================= */

        CASE

            WHEN
            (
                ISNULL(
                (
                    SELECT SUM(Q.BALANCE_AMOUNT)
                    FROM
                    (
                        SELECT
                            I.REFCODE,

                            (
                                ABS(ISNULL(I.VALUE1,0))

                                +

                                /* DR NOTE */
                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                                    FROM TRAN3 DR
                                    WHERE
                                        DR.REFCODE = I.REFCODE
                                        AND DR.VCHTYPE = 17
                                        AND DR.TYPE = 2
                                        AND DR.STATUS = 1
                                ),0)

                                -

                                /* CR NOTE + RECEIPT + RETURN */
                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                    FROM TRAN3 P
                                    WHERE
                                        P.REFCODE = I.REFCODE
                                        AND P.VCHTYPE IN (14,3,16,18)
                                        AND P.TYPE = 2
                                        AND P.STATUS = 1
                                        AND P.METHOD = 2
                                ),0)

                            ) AS BALANCE_AMOUNT,

                            I.DUEDATE

                        FROM TRAN3 I

                        WHERE
                            I.MASTERCODE1 = M.CODE
                            AND I.VCHTYPE IN (1,9,16,19)
                            AND I.TYPE = 1
                            AND I.STATUS IN (1,2)

                    ) Q

                    WHERE
                        Q.BALANCE_AMOUNT > 0
                        AND Q.DUEDATE <= GETDATE()

                ),0)

                -

                CASE
                    WHEN ISNULL(F.D1,0) > 0
                    THEN F.D1
                    ELSE 0
                END

            ) < 0

            THEN 0

            ELSE

                ISNULL(
                (
                    SELECT SUM(Q.BALANCE_AMOUNT)
                    FROM
                    (
                        SELECT
                            I.REFCODE,

                            (
                                ABS(ISNULL(I.VALUE1,0))

                                +

                                /* DR NOTE */
                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                                    FROM TRAN3 DR
                                    WHERE
                                        DR.REFCODE = I.REFCODE
                                        AND DR.VCHTYPE = 17
                                        AND DR.TYPE = 2
                                        AND DR.STATUS = 1
                                ),0)

                                -

                                /* CR NOTE + RECEIPT + RETURN */
                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                    FROM TRAN3 P
                                    WHERE
                                        P.REFCODE = I.REFCODE
                                        AND P.VCHTYPE IN (14,3,16,18)
                                        AND P.TYPE = 2
                                        AND P.STATUS = 1
                                        AND P.METHOD = 2
                                ),0)

                            ) AS BALANCE_AMOUNT,

                            I.DUEDATE

                        FROM TRAN3 I

                        WHERE
                            I.MASTERCODE1 = M.CODE
                            AND I.VCHTYPE IN (1,9,16,19)
                            AND I.TYPE = 1
                            AND I.STATUS IN (1,2)

                    ) Q

                    WHERE
                        Q.BALANCE_AMOUNT > 0
                        AND Q.DUEDATE <= GETDATE()

                ),0)

                -

                CASE
                    WHEN ISNULL(F.D1,0) > 0
                    THEN F.D1
                    ELSE 0
                END

        END AS AMOUNT_ALREADY_DUE_NET_OF_ADVANCE,


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

                    (
                        /* ORIGINAL INVOICE */
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* CR NOTE - 18 + RECEIPT + RETURN */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE > GETDATE()

        ),0) AS FUTURE_DUE_AMOUNT,


        /* =========================================
           AGE 0 - 30 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    (
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* CR NOTE - 18 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 0 AND 30

        ),0) AS AGE_0_30,


        /* =========================================
           AGE 31 - 60 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    (
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* CR NOTE - 18 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 31 AND 60

        ),0) AS AGE_31_60,


        /* =========================================
           AGE 61 - 90 DAYS
           ========================================= */

        ISNULL(
        (
            SELECT SUM(Q.BALANCE_AMOUNT)
            FROM
            (
                SELECT
                    I.REFCODE,

                    (
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* CR NOTE - 18 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()
                AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) BETWEEN 61 AND 90

        ),0) AS AGE_61_90,


        /* =========================================
           AGE 90+ DAYS (NET OF ADVANCE)
           ========================================= */

        CASE
            WHEN
            (
                ISNULL(
                (
                    SELECT SUM(Q.BALANCE_AMOUNT)
                    FROM
                    (
                        SELECT
                            I.REFCODE,

                            (
                                ABS(ISNULL(I.VALUE1,0))

                                +

                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                                    FROM TRAN3 DR
                                    WHERE
                                        DR.REFCODE = I.REFCODE
                                        AND DR.VCHTYPE = 17
                                        AND DR.TYPE = 2
                                        AND DR.STATUS = 1
                                ),0)

                                -

                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                    FROM TRAN3 P
                                    WHERE
                                        P.REFCODE = I.REFCODE
                                        AND P.VCHTYPE IN (14,3,16,18)
                                        AND P.TYPE = 2
                                        AND P.STATUS = 1
                                        AND P.METHOD = 2
                                ),0)

                            ) AS BALANCE_AMOUNT,

                            I.DUEDATE

                        FROM TRAN3 I

                        WHERE
                            I.MASTERCODE1 = M.CODE
                            AND I.VCHTYPE IN (1,9,16,19)
                            AND I.TYPE = 1
                            AND I.STATUS IN (1,2)

                    ) Q

                    WHERE
                        Q.BALANCE_AMOUNT > 0
                        AND Q.DUEDATE <= GETDATE()
                        AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) > 90

                ),0)
                -
                CASE
                    WHEN ISNULL(F.D1,0) > 0
                    THEN F.D1
                    ELSE 0
                END
            ) < 0
            THEN 0

            ELSE
                ISNULL(
                (
                    SELECT SUM(Q.BALANCE_AMOUNT)
                    FROM
                    (
                        SELECT
                            I.REFCODE,

                            (
                                ABS(ISNULL(I.VALUE1,0))

                                +

                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                                    FROM TRAN3 DR
                                    WHERE
                                        DR.REFCODE = I.REFCODE
                                        AND DR.VCHTYPE = 17
                                        AND DR.TYPE = 2
                                        AND DR.STATUS = 1
                                ),0)

                                -

                                ISNULL(
                                (
                                    SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                                    FROM TRAN3 P
                                    WHERE
                                        P.REFCODE = I.REFCODE
                                        AND P.VCHTYPE IN (14,3,16,18)
                                        AND P.TYPE = 2
                                        AND P.STATUS = 1
                                        AND P.METHOD = 2
                                ),0)

                            ) AS BALANCE_AMOUNT,

                            I.DUEDATE

                        FROM TRAN3 I

                        WHERE
                            I.MASTERCODE1 = M.CODE
                            AND I.VCHTYPE IN (1,9,16,19)
                            AND I.TYPE = 1
                            AND I.STATUS IN (1,2)

                    ) Q

                    WHERE
                        Q.BALANCE_AMOUNT > 0
                        AND Q.DUEDATE <= GETDATE()
                        AND DATEDIFF(DAY,Q.DUEDATE,GETDATE()) > 90

                ),0)
                -
                CASE
                    WHEN ISNULL(F.D1,0) > 0
                    THEN F.D1
                    ELSE 0
                END
        END AS AGE_90_PLUS,


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

                    (
                        ABS(ISNULL(I.VALUE1,0))

                        +

                        /* DR NOTE - 17 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(DR.VALUE1,0)))
                            FROM TRAN3 DR
                            WHERE
                                DR.REFCODE = I.REFCODE
                                AND DR.VCHTYPE = 17
                                AND DR.TYPE = 2
                                AND DR.STATUS = 1
                        ),0)

                        -

                        /* CR NOTE - 18 */
                        ISNULL(
                        (
                            SELECT SUM(ABS(ISNULL(P.VALUE1,0)))
                            FROM TRAN3 P
                            WHERE
                                P.REFCODE = I.REFCODE
                                AND P.VCHTYPE IN (14,3,16,18)
                                AND P.TYPE = 2
                                AND P.STATUS = 1
                                AND P.METHOD = 2
                        ),0)

                    ) AS BALANCE_AMOUNT,

                    I.DUEDATE

                FROM TRAN3 I

                WHERE
                    I.MASTERCODE1 = M.CODE
                    AND I.VCHTYPE IN (1,9,16,19)
                    AND I.TYPE = 1
                    AND I.STATUS IN (1,2)

            ) Q

            WHERE
                Q.BALANCE_AMOUNT > 0
                AND Q.DUEDATE <= GETDATE()

        ),0) AS MAX_DAYS_OVERDUE,


        /* =========================================
           LAST INVOICE DATE
           ========================================= */

        (
            SELECT TOP 1 T.[Date]
            FROM TRAN3 T
            WHERE
                T.MASTERCODE1 = M.CODE
                AND T.VCHTYPE = 9
                AND T.TYPE = 1
                AND T.STATUS IN (1,2)
            ORDER BY
                T.[Date] DESC,
                T.VchCode DESC
        ) AS LAST_INVOICE_DATE,


        /* =========================================
           LAST INVOICE AMOUNT
           ========================================= */

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
                    ORDER BY
                        T3.[Date] DESC,
                        T3.VchCode DESC
                )
        ) AS LAST_INVOICE_AMOUNT,


        /* =========================================
           LAST RECEIPT DATE
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
            ORDER BY
                T.[Date] DESC,
                T.VchCode DESC
        ) AS LAST_RECEIPT_DATE,


        /* =========================================
           LAST RECEIPT AMOUNT
           ========================================= */

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
                    ORDER BY
                        T3.[Date] DESC,
                        T3.VchCode DESC
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


        /* =========================================
           SALESMAN
           ========================================= */

        (
            SELECT TOP 1 S.NAME
            FROM MASTER1 S
            WHERE
                S.CODE = TRY_CONVERT(INT, A.OF2)
        ) AS SALESMAN,

        TRY_CONVERT(INT, A.OF2) AS SALESMANCODE,


        /* =========================================
           CREDIT TERMS
           ========================================= */

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
