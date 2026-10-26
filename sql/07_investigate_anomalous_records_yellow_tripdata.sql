SELECT
    fare_amount < 0 AS negative_fare,
    tip_amount < 0 AS negative_tip,
    tolls_amount < 0 AS negative_tolls,
    COUNT(*) AS row_count,
    ROUND(AVG(total_amount), 2) AS avg_total
FROM raw.yellow_tripdata
WHERE total_amount < 0
GROUP BY
    fare_amount < 0,
    tip_amount < 0,
    tolls_amount < 0
ORDER BY row_count DESC;