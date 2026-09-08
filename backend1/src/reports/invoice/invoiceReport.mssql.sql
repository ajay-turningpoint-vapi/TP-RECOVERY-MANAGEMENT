SELECT
    B.RefCode AS ref_code,
    B.MasterCode1 AS customer_id,
    M.Name AS customer_name,
    B.Date AS invoice_date,
    B.DueDate AS due_date,
    B.No AS invoice_no,
    ABS(B.BillAmount) AS ref_amount,
    ABS(B.BillAmount) - ISNULL(A.AdjAmount,0) AS pending_amount,
    CASE
        WHEN DATEDIFF(DAY,B.DueDate,GETDATE()) > M.I2
             THEN 'EXCEEDED CREDIT DAYS'
        ELSE 'WITHIN CREDIT DAYS'
    END AS message
FROM
(
    SELECT
        RefCode,
        Date,
        DueDate,
        No,
        MasterCode1,
        Value1 AS BillAmount
    FROM TRAN3
    WHERE Method = 1
      AND Type = 1
      AND VchType IN (1,9)      
) B
LEFT JOIN
(
    SELECT
        RefCode,
        SUM(ABS(Value1)) AS AdjAmount
    FROM TRAN3
    WHERE Method = 2
      AND Type = 2
    GROUP BY RefCode
) A
ON B.RefCode = A.RefCode
INNER JOIN MASTER1 M
    ON M.Code = B.MasterCode1
WHERE
    M.MasterType = 2
    /*{{CUSTOMER_FILTER}}*/
    AND (ABS(B.BillAmount) - ISNULL(A.AdjAmount,0)) > 0
ORDER BY
    B.DueDate
