BEGIN;

CREATE SCHEMA IF NOT EXISTS staging;

CREATE TABLE IF NOT EXISTS staging.yellow_tripdata (
    raw_trip_record_id BIGINT PRIMARY KEY,

    vendor_id SMALLINT,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count SMALLINT,
    trip_distance NUMERIC(8, 2),
    ratecode_id SMALLINT,
    store_and_fwd_flag CHAR(1),
    pickup_location_id SMALLINT,
    dropoff_location_id SMALLINT,
    payment_type SMALLINT,

    fare_amount NUMERIC(8, 2),
    extra NUMERIC(5, 2),
    mta_tax NUMERIC(4, 2),
    tip_amount NUMERIC(7, 2),
    tolls_amount NUMERIC(5, 2),
    improvement_surcharge NUMERIC(4, 2),
    total_amount NUMERIC(9, 2),
    congestion_surcharge NUMERIC(4, 2),
    airport_fee NUMERIC(5, 2),
    cbd_congestion_fee NUMERIC(4, 2),

    trip_duration_minutes NUMERIC(10, 2),

    is_negative_duration BOOLEAN NOT NULL,
    is_zero_distance BOOLEAN NOT NULL,
    is_negative_fare BOOLEAN NOT NULL,
    is_negative_total BOOLEAN NOT NULL,
    has_missing_critical_fields BOOLEAN NOT NULL,

    loaded_at TIMESTAMPTZ,
    source_file TEXT
);

-- Full refresh: raw remains untouched
TRUNCATE TABLE staging.yellow_tripdata;

INSERT INTO staging.yellow_tripdata (
    raw_trip_record_id,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance,
    ratecode_id,
    store_and_fwd_flag,
    pickup_location_id,
    dropoff_location_id,
    payment_type,
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
    trip_duration_minutes,
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
    r.vendorid,
    r.tpep_pickup_datetime,
    r.tpep_dropoff_datetime,
    r.passenger_count,
    r.trip_distance,
    r.ratecodeid,
    r.store_and_fwd_flag,
    r.pulocationid,
    r.dolocationid,
    r.payment_type,
    r.fare_amount,
    r.extra,
    r.mta_tax,
    r.tip_amount,
    r.tolls_amount,
    r.improvement_surcharge,
    r.total_amount,
    r.congestion_surcharge,
    r.airport_fee,
    r.cbd_congestion_fee,

    CASE
        WHEN
			r.tpep_pickup_datetime IS NOT NULL
        	AND r.tpep_dropoff_datetime IS NOT NULL
        THEN ROUND(
            (
                EXTRACT(
                    EPOCH FROM (
                        r.tpep_dropoff_datetime
                        - r.tpep_pickup_datetime
                    )
                ) / 60.0
            )::NUMERIC, 2
        )
        ELSE NULL
    END,

    COALESCE(
        r.tpep_dropoff_datetime < r.tpep_pickup_datetime,
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

FROM raw.yellow_tripdata AS r;

COMMIT;