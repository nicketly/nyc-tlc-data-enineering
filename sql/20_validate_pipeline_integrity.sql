-- Read-only integrity checks for the Raw -> Staging -> DWH pipeline.
-- Run after sql/10, sql/12, sql/13, sql/14, and sql/15.
-- Expected healthy result for the current dataset: row counts match,
-- no missing/extra IDs, no duplicate fact IDs, no field mismatches,
-- and no missing dimension keys.

WITH
raw_stats AS (
    SELECT
        COUNT(*) AS raw_rows,
        COUNT(DISTINCT trip_record_id) AS raw_distinct_ids
    FROM raw.yellow_tripdata
),
staging_stats AS (
    SELECT
        COUNT(*) AS staging_rows,
        COUNT(DISTINCT raw_trip_record_id) AS staging_distinct_ids
    FROM staging.yellow_tripdata
),
fact_stats AS (
    SELECT
        COUNT(*) AS fact_rows,
        COUNT(DISTINCT raw_trip_record_id) AS fact_distinct_ids,
        COUNT(*) FILTER (WHERE pickup_date_key IS NULL) AS missing_pickup_date_keys,
        COUNT(*) FILTER (WHERE dropoff_date_key IS NULL) AS missing_dropoff_date_keys,
        COUNT(*) FILTER (WHERE vendor_key IS NULL) AS missing_vendor_keys,
        COUNT(*) FILTER (WHERE payment_type_key IS NULL) AS missing_payment_type_keys,
        COUNT(*) FILTER (WHERE ratecode_key IS NULL) AS missing_ratecode_keys,
        COUNT(*) FILTER (WHERE pickup_location_key IS NULL) AS missing_pickup_location_keys,
        COUNT(*) FILTER (WHERE dropoff_location_key IS NULL) AS missing_dropoff_location_keys
    FROM dwh.fact_trips
),
coverage AS (
    SELECT
        (SELECT COUNT(*)
         FROM raw.yellow_tripdata r
         LEFT JOIN staging.yellow_tripdata s
           ON s.raw_trip_record_id = r.trip_record_id
         WHERE s.raw_trip_record_id IS NULL) AS raw_missing_from_staging,
        (SELECT COUNT(*)
         FROM staging.yellow_tripdata s
         LEFT JOIN raw.yellow_tripdata r
           ON r.trip_record_id = s.raw_trip_record_id
         WHERE r.trip_record_id IS NULL) AS staging_without_raw,
        (SELECT COUNT(*)
         FROM staging.yellow_tripdata s
         LEFT JOIN dwh.fact_trips f
           ON f.raw_trip_record_id = s.raw_trip_record_id
         WHERE f.raw_trip_record_id IS NULL) AS staging_missing_from_fact,
        (SELECT COUNT(*)
         FROM dwh.fact_trips f
         LEFT JOIN staging.yellow_tripdata s
           ON s.raw_trip_record_id = f.raw_trip_record_id
         WHERE s.raw_trip_record_id IS NULL) AS fact_without_staging
),
parity AS (
    SELECT
        COUNT(*) AS matched_staging_fact_records,
        COUNT(*) FILTER (
            WHERE s.trip_duration_minutes IS DISTINCT FROM f.trip_duration_minutes
        ) AS duration_mismatches,
        COUNT(*) FILTER (
            WHERE s.is_negative_duration IS DISTINCT FROM f.is_negative_duration
        ) AS negative_duration_flag_mismatches,
        COUNT(*) FILTER (
            WHERE s.is_zero_distance IS DISTINCT FROM f.is_zero_distance
        ) AS zero_distance_flag_mismatches,
        COUNT(*) FILTER (
            WHERE s.is_negative_fare IS DISTINCT FROM f.is_negative_fare
        ) AS negative_fare_flag_mismatches,
        COUNT(*) FILTER (
            WHERE s.is_negative_total IS DISTINCT FROM f.is_negative_total
        ) AS negative_total_flag_mismatches,
        COUNT(*) FILTER (
            WHERE s.has_missing_critical_fields
                  IS DISTINCT FROM f.has_missing_critical_fields
        ) AS missing_field_flag_mismatches,
        COUNT(*) FILTER (
            WHERE s.trip_distance IS DISTINCT FROM f.trip_distance
               OR s.fare_amount IS DISTINCT FROM f.fare_amount
               OR s.total_amount IS DISTINCT FROM f.total_amount
               OR s.pickup_datetime IS DISTINCT FROM f.pickup_datetime
               OR s.dropoff_datetime IS DISTINCT FROM f.dropoff_datetime
        ) AS source_value_mismatches
    FROM staging.yellow_tripdata s
    JOIN dwh.fact_trips f
      ON f.raw_trip_record_id = s.raw_trip_record_id
)
SELECT
    r.raw_rows,
    r.raw_distinct_ids,
    s.staging_rows,
    s.staging_distinct_ids,
    f.fact_rows,
    f.fact_distinct_ids,
    c.raw_missing_from_staging,
    c.staging_without_raw,
    c.staging_missing_from_fact,
    c.fact_without_staging,
    p.matched_staging_fact_records,
    p.duration_mismatches,
    p.negative_duration_flag_mismatches,
    p.zero_distance_flag_mismatches,
    p.negative_fare_flag_mismatches,
    p.negative_total_flag_mismatches,
    p.missing_field_flag_mismatches,
    p.source_value_mismatches,
    f.missing_pickup_date_keys,
    f.missing_dropoff_date_keys,
    f.missing_vendor_keys,
    f.missing_payment_type_keys,
    f.missing_ratecode_keys,
    f.missing_pickup_location_keys,
    f.missing_dropoff_location_keys
FROM raw_stats r
CROSS JOIN staging_stats s
CROSS JOIN fact_stats f
CROSS JOIN coverage c
CROSS JOIN parity p;
