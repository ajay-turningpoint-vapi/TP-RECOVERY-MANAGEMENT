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
    AND CONVERT(DATE, T.[Date]) >= '2026-09-04'
    AND CONVERT(DATE, T.[Date]) <= '2026-09-05'

GROUP BY
    M.CODE,
    M.NAME

ORDER BY
    M.NAME
