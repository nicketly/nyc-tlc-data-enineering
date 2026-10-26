SELECT
    COUNT(*) FILTER (
        WHERE tpep_dropoff_datetime < tpep_pickup_datetime
    ) AS negative_duration,
    COUNT(*) FILTER (
        WHERE trip_distance < 0
    ) AS negative_distance,
    COUNT(*) FILTER (
        WHERE fare_amount < 0
    ) AS negative_fare,
    COUNT(*) FILTER (
        WHERE total_amount < 0
    ) AS negative_total,
    COUNT(*) FILTER (
        WHERE trip_distance = 0
    ) AS zero_distance
FROM raw.yellow_tripdata;