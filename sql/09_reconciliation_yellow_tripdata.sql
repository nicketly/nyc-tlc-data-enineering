WITH reconciliation AS (
    SELECT
        VendorID,
        payment_type,
        ROUND(
            total_amount - (
                fare_amount
                + extra
                + mta_tax
                + tip_amount
                + tolls_amount
                + improvement_surcharge
            ),
            2
        ) AS difference_base,
        ROUND(
            total_amount - (
                fare_amount
                + extra
                + mta_tax
                + tip_amount
                + tolls_amount
                + improvement_surcharge
                + COALESCE(congestion_surcharge, 0)
            ),
            2
        ) AS difference_with_congestion,
        ROUND(
            total_amount - (
                fare_amount
                + extra
                + mta_tax
                + tip_amount
                + tolls_amount
                + improvement_surcharge
                + COALESCE(congestion_surcharge, 0)
                + COALESCE(Airport_fee, 0)
                + COALESCE(cbd_congestion_fee, 0)
            ),
            2
        ) AS difference_with_all_fees
    FROM raw.yellow_tripdata
)
SELECT
    payment_type,
    VendorID,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE difference_base = 0
    ) AS matches_base,
    COUNT(*) FILTER (
        WHERE difference_with_congestion = 0
    ) AS matches_with_congestion,
    COUNT(*) FILTER (
        WHERE difference_with_all_fees = 0
    ) AS matches_with_all_fees
FROM reconciliation
GROUP BY payment_type, VendorID
ORDER BY total_rows DESC;