/*
 * Canonical customer ledger report against BUSY (MSSQL) — the production
 * query backing MssqlCustomerReportRepository. Based on the updated
 * query supplied directly (narrower than the earlier version: no
 * OPENING_OUTSTANDING / CURRENT_YEAR_* / LAST_RECEIPT_* / EMAIL /
 * AS_OF_DATE, and no salesman-code filter — scoped by PARENTGRP only).
 *
 * Two deliberate deviations from the supplied query, both proven
 * necessary against this exact BUSY data (not speculative):
 *  1. TRY_CONVERT(INT, ...) around A.OF2 / M.I2 and TRY_CONVERT(DECIMAL, ...)
 *     around M.D1 — these columns are declared numeric-ish but contain
 *     stray text (e.g. 'INCENTIVE') in some rows; without the guard the
 *     whole query throws "Conversion failed... to data type int" (hit
 *     this for real, twice, on live data).
 *  2. ORDER BY X.CUSTOMER_NAME at the end — the supplied query has none,
 *     which makes row order (and therefore "TOP (n)" previews) arbitrary
 *     between runs. Adding it back changes nothing about which rows
 *     match, only their order.
 *
 * mssqlCustomerReportRepository.ts injects "TOP (n)" into this query's
 * own leading SELECT when options.limit is set.
 */
SELECT X.*
FROM
(
    SELECT

        M.CODE AS CUSTOMER_ID,
        M.NAME AS CUSTOMER_NAME,

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
                                    AND P.VCHTYPE IN (14,3)
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
                                    AND P.VCHTYPE IN (14,3)
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
                                    AND P.VCHTYPE IN (14,3)
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
                                    AND P.VCHTYPE IN (14,3)
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
                            AND P.VCHTYPE IN (14,3)
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
                            AND P.VCHTYPE IN (14,3)
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
                            AND P.VCHTYPE IN (14,3)
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
                            AND P.VCHTYPE IN (14,3)
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
                            AND P.VCHTYPE IN (14,3)
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
           CUSTOMER DETAILS
           ========================================= */

        ISNULL(A.MOBILE,'') AS MOBILE,
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

        AND M.PARENTGRP IN (/*{{PARENTGRP_CODES}}*/)

) X

/* =========================================
   ONLY DR CUSTOMERS
   ========================================= */

WHERE
    X.BALANCE_TYPE = 'DR'
    /*{{SALESMAN_FILTER}}*/

ORDER BY
    X.CUSTOMER_NAME
