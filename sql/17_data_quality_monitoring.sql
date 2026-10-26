-- Data quality monitoring checks for the NYC TLC Yellow Taxi warehouse.
-- Read-only diagnostic queries; run each query independently.
-- Review anomalies before deciding whether to exclude or correct records.

-- 1. Raw ingestion coverage by source file.
SELECT
    source_file,
    COUNT(*) AS raw_row_count,
    MIN(tpep_pickup_datetime) AS first_pickup_datetime,
    MAX(tpep_pickup_datetime) AS last_pickup_datetime,
    COUNT(*) FILTER (WHERE tpep_pickup_datetime IS NULL) AS missing_pickup_datetime,
    COUNT(*) FILTER (WHERE tpep_dropoff_datetime IS NULL) AS missing_dropoff_datetime
FROM raw.yellow_tripdata
GROUP BY source_file
ORDER BY source_file;


-- 2. Source rate-code completeness by payment type.
-- This checks the original raw values, independently of DWH surrogate keys.
SELECT
    payment_type,
    COUNT(*) AS trip_count,
    COUNT(*) FILTER (WHERE RatecodeID IS NULL) AS missing_ratecode_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE RatecodeID IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS missing_ratecode_pct
FROM raw.yellow_tripdata
GROUP BY payment_type
ORDER BY payment_type NULLS LAST;


-- 3. Raw source-code distribution: detect nulls and unexpected values.
SELECT
    RatecodeID,
    COUNT(*) AS trip_count
FROM raw.yellow_tripdata
GROUP BY RatecodeID
ORDER BY RatecodeID NULLS LAST;


-- 4. Compare row counts and unique trip IDs across raw and DWH.
SELECT
    (SELECT COUNT(*) FROM raw.yellow_tripdata) AS raw_rows,
    (SELECT COUNT(*) FROM dwh.fact_trips) AS fact_rows,
    (SELECT COUNT(DISTINCT raw_trip_record_id) FROM dwh.fact_trips) AS unique_fact_trip_ids;


-- 5. Missing dimension keys in the fact table.
SELECT
    COUNT(*) FILTER (WHERE pickup_date_key IS NULL) AS missing_pickup_date_key,
    COUNT(*) FILTER (WHERE dropoff_date_key IS NULL) AS missing_dropoff_date_key,
    COUNT(*) FILTER (WHERE vendor_key IS NULL) AS missing_vendor_key,
    COUNT(*) FILTER (WHERE payment_type_key IS NULL) AS missing_payment_type_key,
    COUNT(*) FILTER (WHERE ratecode_key IS NULL) AS missing_ratecode_key,
    COUNT(*) FILTER (WHERE pickup_location_key IS NULL) AS missing_pickup_location_key,
    COUNT(*) FILTER (WHERE dropoff_location_key IS NULL) AS missing_dropoff_location_key
FROM dwh.fact_trips;


-- 6. Data-quality flag counts.
-- These are diagnostics, not automatic reasons to delete rows.
SELECT
    COUNT(*) AS fact_rows,
    COUNT(*) FILTER (WHERE is_negative_duration) AS negative_duration_rows,
    COUNT(*) FILTER (WHERE is_zero_distance) AS zero_distance_rows,
    COUNT(*) FILTER (WHERE is_negative_fare) AS negative_fare_rows,
    COUNT(*) FILTER (WHERE is_negative_total) AS negative_total_rows,
    COUNT(*) FILTER (WHERE has_missing_critical_fields) AS missing_critical_field_rows
FROM dwh.fact_trips;


-- 7. Inspect the most common combinations of quality flags.
SELECT
    is_negative_duration,
    is_zero_distance,
    is_negative_fare,
    is_negative_total,
    has_missing_critical_fields,
    COUNT(*) AS trip_count
FROM dwh.fact_trips
GROUP BY
    is_negative_duration,
    is_zero_distance,
    is_negative_fare,
    is_negative_total,
    has_missing_critical_fields
ORDER BY trip_count DESC
LIMIT 20;


-- 8. Compare source rate codes with the rate-code dimension mapping.
-- NULL source codes are expected to map to the dedicated missing member (ratecode_id = 0).
SELECT
    d.ratecode_id AS dimension_ratecode_id,
    d.ratecode_description,
    COUNT(*) AS trip_count,
    COUNT(*) FILTER (
        WHERE r.RatecodeID IS DISTINCT FROM d.ratecode_id
          AND NOT (r.RatecodeID IS NULL AND d.ratecode_id = 0)
    ) AS source_code_mismatch_count
FROM dwh.fact_trips AS f
JOIN raw.yellow_tripdata AS r
    ON r.trip_record_id = f.raw_trip_record_id
JOIN dwh.dim_ratecode AS d
    ON d.ratecode_key = f.ratecode_key
GROUP BY d.ratecode_id, d.ratecode_description
ORDER BY trip_count DESC;
