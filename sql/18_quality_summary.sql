-- Compact, repeatable data-quality summary for the NYC TLC Yellow Taxi warehouse.
-- Run after loading raw data and refreshing dwh.fact_trips.
-- Read-only: this script does not modify source or warehouse tables.
--
-- Status meanings:
-- PASS   = structural expectation is met
-- REVIEW = an anomaly exists and should be investigated, not automatically deleted

WITH
raw_stats AS (
    SELECT COUNT(*)::BIGINT AS raw_rows
    FROM raw.yellow_tripdata
),
fact_stats AS (
    SELECT
        COUNT(*)::BIGINT AS fact_rows,
        COUNT(DISTINCT raw_trip_record_id)::BIGINT AS unique_fact_trip_ids,
        COUNT(*) FILTER (WHERE pickup_date_key IS NULL
                          OR dropoff_date_key IS NULL
                          OR vendor_key IS NULL
                          OR payment_type_key IS NULL
                          OR ratecode_key IS NULL
                          OR pickup_location_key IS NULL
                          OR dropoff_location_key IS NULL)::BIGINT AS rows_with_missing_dimension_keys,
        COUNT(*) FILTER (WHERE is_negative_duration)::BIGINT AS negative_duration_rows,
        COUNT(*) FILTER (WHERE is_zero_distance)::BIGINT AS zero_distance_rows,
        COUNT(*) FILTER (WHERE is_negative_fare)::BIGINT AS negative_fare_rows,
        COUNT(*) FILTER (WHERE is_negative_total)::BIGINT AS negative_total_rows,
        COUNT(*) FILTER (WHERE has_missing_critical_fields)::BIGINT AS missing_critical_field_rows
    FROM dwh.fact_trips
),
coverage_stats AS (
    SELECT
        (SELECT COUNT(*)::BIGINT
         FROM raw.yellow_tripdata AS r
         WHERE NOT EXISTS (
             SELECT 1 FROM dwh.fact_trips AS f
             WHERE f.raw_trip_record_id = r.trip_record_id
         )) AS raw_rows_missing_from_fact,
        (SELECT COUNT(*)::BIGINT
         FROM dwh.fact_trips AS f
         WHERE NOT EXISTS (
             SELECT 1 FROM raw.yellow_tripdata AS r
             WHERE r.trip_record_id = f.raw_trip_record_id
         )) AS fact_rows_missing_from_raw
),
ratecode_mismatches AS (
    SELECT COUNT(*)::BIGINT AS mismatch_rows
    FROM dwh.fact_trips AS f
    JOIN raw.yellow_tripdata AS r
        ON r.trip_record_id = f.raw_trip_record_id
    LEFT JOIN dwh.dim_ratecode AS d
        ON d.ratecode_key = f.ratecode_key
    WHERE d.ratecode_key IS NULL
       OR (r.RatecodeID IS NULL AND d.ratecode_id <> 0)
       OR (r.RatecodeID IS NOT NULL AND r.RatecodeID IS DISTINCT FROM d.ratecode_id)
),
metrics AS (
    SELECT
        'raw_to_fact_row_count_difference'::TEXT AS metric_name,
        ABS(r.raw_rows - f.fact_rows)::BIGINT AS metric_value,
        NULLIF(r.raw_rows, 0)::BIGINT AS denominator,
        0::BIGINT AS allowed_value,
        'Raw and fact row counts should match.'::TEXT AS interpretation
    FROM raw_stats AS r CROSS JOIN fact_stats AS f

    UNION ALL
    SELECT
        'raw_rows_missing_from_fact',
        c.raw_rows_missing_from_fact,
        NULLIF(r.raw_rows, 0),
        0,
        'Every raw trip should have a corresponding fact row.'
    FROM coverage_stats AS c CROSS JOIN raw_stats AS r

    UNION ALL
    SELECT
        'fact_rows_missing_from_raw',
        c.fact_rows_missing_from_raw,
        NULLIF(f.fact_rows, 0),
        0,
        'Every fact row should point to an existing raw trip.'
    FROM coverage_stats AS c CROSS JOIN fact_stats AS f

    UNION ALL
    SELECT
        'duplicate_fact_trip_ids',
        f.fact_rows - f.unique_fact_trip_ids,
        NULLIF(f.fact_rows, 0),
        0,
        'Fact rows should have unique raw_trip_record_id values.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'rows_with_missing_dimension_keys',
        f.rows_with_missing_dimension_keys,
        NULLIF(f.fact_rows, 0),
        0,
        'Every fact row should resolve to all required dimension members.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'ratecode_source_mapping_mismatches',
        m.mismatch_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Source RatecodeID should match its dimension member; source NULL maps to ratecode_id 0.'
    FROM ratecode_mismatches AS m CROSS JOIN fact_stats AS f

    UNION ALL
    SELECT
        'negative_duration_rows',
        f.negative_duration_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Investigate trips where drop-off precedes pick-up.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'zero_distance_rows',
        f.zero_distance_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Zero distance may reflect invalid data or special trip circumstances.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'negative_fare_rows',
        f.negative_fare_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Investigate negative fares before deciding how to treat them.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'negative_total_amount_rows',
        f.negative_total_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Investigate negative total amounts; do not automatically remove them.'
    FROM fact_stats AS f

    UNION ALL
    SELECT
        'rows_with_missing_critical_fields',
        f.missing_critical_field_rows,
        NULLIF(f.fact_rows, 0),
        0,
        'Critical-field completeness should be reviewed.'
    FROM fact_stats AS f
)
SELECT
    metric_name,
    metric_value,
    ROUND(100.0 * metric_value / NULLIF(denominator, 0), 4) AS pct_of_fact_rows,
    allowed_value,
    CASE WHEN metric_value <= allowed_value THEN 'PASS' ELSE 'REVIEW' END AS status,
    interpretation
FROM metrics
ORDER BY
    CASE WHEN metric_value > allowed_value THEN 0 ELSE 1 END,
    metric_name;
