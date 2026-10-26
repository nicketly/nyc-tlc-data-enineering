BEGIN;

-- Add the rate-code surrogate key to the fact table if this is an upgrade.
ALTER TABLE dwh.fact_trips
    ADD COLUMN IF NOT EXISTS ratecode_key INTEGER
        REFERENCES dwh.dim_ratecode(ratecode_key);

-- Load transformed records from staging rather than recalculating fields
-- from raw. This keeps transformation logic in one layer.
-- The rate-code key 0 represents a NULL source RatecodeID.
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
    s.raw_trip_record_id,
    TO_CHAR(s.pickup_datetime::DATE, 'YYYYMMDD')::INTEGER,
    TO_CHAR(s.dropoff_datetime::DATE, 'YYYYMMDD')::INTEGER,
    v.vendor_key,
    p.payment_type_key,
    COALESCE(rc.ratecode_key, 0),
    pu.location_key,
    doff.location_key,
    s.pickup_datetime,
    s.dropoff_datetime,
    s.passenger_count,
    s.trip_distance,
    s.trip_duration_minutes,
    s.fare_amount,
    s.extra,
    s.mta_tax,
    s.tip_amount,
    s.tolls_amount,
    s.improvement_surcharge,
    s.total_amount,
    s.congestion_surcharge,
    s.airport_fee,
    s.cbd_congestion_fee,
    s.is_negative_duration,
    s.is_zero_distance,
    s.is_negative_fare,
    s.is_negative_total,
    s.has_missing_critical_fields,
    s.loaded_at,
    s.source_file
FROM staging.yellow_tripdata AS s
LEFT JOIN dwh.dim_vendor AS v
    ON v.vendor_id = s.vendor_id
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_id = s.payment_type
LEFT JOIN dwh.dim_ratecode AS rc
    ON rc.ratecode_id = s.ratecode_id
LEFT JOIN dwh.dim_location AS pu
    ON pu.location_id = s.pickup_location_id
LEFT JOIN dwh.dim_location AS doff
    ON doff.location_id = s.dropoff_location_id
ON CONFLICT (raw_trip_record_id) DO UPDATE SET
    pickup_date_key = EXCLUDED.pickup_date_key,
    dropoff_date_key = EXCLUDED.dropoff_date_key,
    vendor_key = EXCLUDED.vendor_key,
    payment_type_key = EXCLUDED.payment_type_key,
    ratecode_key = EXCLUDED.ratecode_key,
    pickup_location_key = EXCLUDED.pickup_location_key,
    dropoff_location_key = EXCLUDED.dropoff_location_key,
    pickup_datetime = EXCLUDED.pickup_datetime,
    dropoff_datetime = EXCLUDED.dropoff_datetime,
    passenger_count = EXCLUDED.passenger_count,
    trip_distance = EXCLUDED.trip_distance,
    trip_duration_minutes = EXCLUDED.trip_duration_minutes,
    fare_amount = EXCLUDED.fare_amount,
    extra = EXCLUDED.extra,
    mta_tax = EXCLUDED.mta_tax,
    tip_amount = EXCLUDED.tip_amount,
    tolls_amount = EXCLUDED.tolls_amount,
    improvement_surcharge = EXCLUDED.improvement_surcharge,
    total_amount = EXCLUDED.total_amount,
    congestion_surcharge = EXCLUDED.congestion_surcharge,
    airport_fee = EXCLUDED.airport_fee,
    cbd_congestion_fee = EXCLUDED.cbd_congestion_fee,
    is_negative_duration = EXCLUDED.is_negative_duration,
    is_zero_distance = EXCLUDED.is_zero_distance,
    is_negative_fare = EXCLUDED.is_negative_fare,
    is_negative_total = EXCLUDED.is_negative_total,
    has_missing_critical_fields = EXCLUDED.has_missing_critical_fields,
    loaded_at = EXCLUDED.loaded_at,
    source_file = EXCLUDED.source_file;

COMMIT;
