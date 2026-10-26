SELECT
    payment_type,
    COUNT(*) AS row_count,
    MIN(fare_amount) AS min_fare,
    MAX(fare_amount) AS max_fare,
    MIN(extra) AS min_extra,
    MAX(extra) AS max_extra,
    MIN(mta_tax) AS min_mta_tax,
    MAX(mta_tax) AS max_mta_tax,
    MIN(improvement_surcharge) AS min_improvement_surcharge,
    MAX(improvement_surcharge) AS max_improvement_surcharge,
    MIN(congestion_surcharge) AS min_congestion_surcharge,
    MAX(congestion_surcharge) AS max_congestion_surcharge,
    MIN(total_amount) AS min_total,
    MAX(total_amount) AS max_total
FROM raw.yellow_tripdata
WHERE total_amount < 0
  AND fare_amount >= 0
  AND tip_amount >= 0
  AND tolls_amount >= 0
GROUP BY payment_type
ORDER BY row_count DESC;