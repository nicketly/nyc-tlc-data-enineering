BEGIN;

-- Add the rate-code surrogate key to the fact table.
ALTER TABLE dwh.fact_trips
    ADD COLUMN IF NOT EXISTS ratecode_key INTEGER
        REFERENCES dwh.dim_ratecode(ratecode_key);


-- Load one warehouse fact row per raw trip record.
-- LEFT JOINs preserve trips even when a dimension lookup is unavailable.
INSERT INTO dwh.fact_trips (
    raw_trip_record_id,
    pickup_date_key,
    dropoff_date_key,
    vendor_key,
    payment_type_key,
    ratecode_key,
    pickup_location_key,
    dropoff_location_key,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance,
    trip_duration_minutes,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,
    is_negative_duration,
    is_zero_distance,
    is_negative_fare,
    is_negative_total,
    has_missing_critical_fields,
    loaded_at,
    source_file
)
SELECT
    r.trip_record_id,
    TO_CHAR(r.tpep_pickup_datetime::DATE, 'YYYYMMDD')::INTEGER,
    TO_CHAR(r.tpep_dropoff_datetime::DATE, 'YYYYMMDD')::INTEGER,
    v.vendor_key,
    p.payment_type_key,
    rc.ratecode_key,
    pu.location_key,
    doff.location_key,
    r.tpep_pickup_datetime,
    r.tpep_dropoff_datetime,
    r.passenger_count,
    r.trip_distance,
    CASE
        WHEN r.tpep_pickup_datetime IS NOT NULL
         AND r.tpep_dropoff_datetime IS NOT NULL
        THEN EXTRACT(EPOCH FROM (
            r.tpep_dropoff_datetime - r.tpep_pickup_datetime
        )) / 60.0
        ELSE NULL
    END,
    r.fare_amount,
    r.extra,
    r.mta_tax,
    r.tip_amount,
    r.tolls_amount,
    r.improvement_surcharge,
    r.total_amount,
    r.congestion_surcharge,
    r.Airport_fee,
    r.cbd_congestion_fee,
    COALESCE(
        r.tpep_pickup_datetime IS NOT NULL
        AND r.tpep_dropoff_datetime IS NOT NULL
        AND r.tpep_dropoff_datetime < r.tpep_pickup_datetime,
        FALSE
    ),
    COALESCE(r.trip_distance = 0, FALSE),
    COALESCE(r.fare_amount < 0, FALSE),
    COALESCE(r.total_amount < 0, FALSE),
    (
        r.tpep_pickup_datetime IS NULL
        OR r.tpep_dropoff_datetime IS NULL
        OR r.trip_distance IS NULL
        OR r.fare_amount IS NULL
        OR r.total_amount IS NULL
    ),
    r.loaded_at,
    r.source_file
FROM raw.yellow_tripdata AS r
LEFT JOIN dwh.dim_vendor AS v
    ON v.vendor_id = r.VendorID
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_id = r.payment_type
LEFT JOIN dwh.dim_ratecode AS rc
    ON rc.ratecode_id = r.RatecodeID
LEFT JOIN dwh.dim_location AS pu
    ON pu.location_id = r.PULocationID
LEFT JOIN dwh.dim_location AS doff
    ON doff.location_id = r.DOLocationID
ON CONFLICT (raw_trip_record_id) DO NOTHING;

COMMIT;
