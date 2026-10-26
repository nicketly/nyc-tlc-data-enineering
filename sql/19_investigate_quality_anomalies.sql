-- Investigate records flagged by the DWH data-quality checks.
-- Read-only diagnostics: no rows are changed or deleted.
-- Run the queries independently and review sample records before defining cleaning rules.

-- 1. Inspect all negative-duration trips (expected to be very few).
SELECT
    raw_trip_record_id,
    source_file,
    pickup_datetime,
    dropoff_datetime,
    trip_duration_minutes,
    trip_distance,
    fare_amount,
    total_amount,
    vendor_key,
    payment_type_key,
    ratecode_key,
    is_negative_duration,
    is_zero_distance,
    is_negative_fare,
    is_negative_total
FROM dwh.fact_trips
WHERE is_negative_duration
ORDER BY pickup_datetime
LIMIT 100;


-- 2. Negative fare / total amounts by payment type and rate code.
-- Counts can overlap: a trip may have both a negative fare and negative total.
SELECT
    p.payment_type_id,
    p.payment_type_description,
    r.ratecode_id,
    r.ratecode_description,
    COUNT(*) AS trip_count,
    COUNT(*) FILTER (WHERE f.is_negative_fare) AS negative_fare_count,
    COUNT(*) FILTER (WHERE f.is_negative_total) AS negative_total_count,
    ROUND(AVG(f.fare_amount), 2) AS avg_fare_amount,
    ROUND(AVG(f.total_amount), 2) AS avg_total_amount,
    MIN(f.fare_amount) AS min_fare_amount,
    MIN(f.total_amount) AS min_total_amount
FROM dwh.fact_trips AS f
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_key = f.payment_type_key
LEFT JOIN dwh.dim_ratecode AS r
    ON r.ratecode_key = f.ratecode_key
WHERE f.is_negative_fare OR f.is_negative_total
GROUP BY
    p.payment_type_id,
    p.payment_type_description,
    r.ratecode_id,
    r.ratecode_description
ORDER BY (COUNT(*) FILTER (WHERE f.is_negative_total)) DESC,
         (COUNT(*) FILTER (WHERE f.is_negative_fare)) DESC;


-- 3. Negative amounts by vendor and payment type.
SELECT
    v.vendor_id,
    v.vendor_name,
    p.payment_type_id,
    p.payment_type_description,
    COUNT(*) AS trip_count,
    COUNT(*) FILTER (WHERE f.is_negative_fare) AS negative_fare_count,
    COUNT(*) FILTER (WHERE f.is_negative_total) AS negative_total_count
FROM dwh.fact_trips AS f
LEFT JOIN dwh.dim_vendor AS v
    ON v.vendor_key = f.vendor_key
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_key = f.payment_type_key
WHERE f.is_negative_fare OR f.is_negative_total
GROUP BY
    v.vendor_id,
    v.vendor_name,
    p.payment_type_id,
    p.payment_type_description
ORDER BY negative_total_count DESC, negative_fare_count DESC;


-- 4. Zero-distance trips by payment type and amount pattern.
SELECT
    p.payment_type_id,
    p.payment_type_description,
    COUNT(*) AS zero_distance_trips,
    COUNT(*) FILTER (WHERE f.fare_amount = 0) AS zero_fare_trips,
    COUNT(*) FILTER (WHERE f.fare_amount > 0) AS positive_fare_trips,
    COUNT(*) FILTER (WHERE f.fare_amount < 0) AS negative_fare_trips,
    COUNT(*) FILTER (WHERE f.total_amount < 0) AS negative_total_trips,
    ROUND(AVG(f.trip_duration_minutes), 2) AS avg_duration_minutes,
    ROUND(AVG(f.fare_amount), 2) AS avg_fare_amount,
    ROUND(AVG(f.total_amount), 2) AS avg_total_amount
FROM dwh.fact_trips AS f
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_key = f.payment_type_key
WHERE f.is_zero_distance
GROUP BY p.payment_type_id, p.payment_type_description
ORDER BY zero_distance_trips DESC;


-- 5. Inspect a sample of negative-amount records.
-- Use this to understand individual records after reviewing aggregate patterns.
SELECT
    raw_trip_record_id,
    source_file,
    pickup_datetime,
    dropoff_datetime,
    trip_duration_minutes,
    trip_distance,
    fare_amount,
    tip_amount,
    tolls_amount,
    total_amount,
    vendor_key,
    payment_type_key,
    ratecode_key,
    is_negative_fare,
    is_negative_total,
    is_zero_distance
FROM dwh.fact_trips
WHERE is_negative_fare OR is_negative_total
ORDER BY total_amount ASC, fare_amount ASC
LIMIT 100;
