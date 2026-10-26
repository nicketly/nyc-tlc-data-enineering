BEGIN;

CREATE SCHEMA IF NOT EXISTS dwh;

-- Calendar dimension
CREATE TABLE IF NOT EXISTS dwh.dim_date (
    date_key INTEGER PRIMARY KEY, -- YYYYMMDD
    full_date DATE NOT NULL UNIQUE,
    year SMALLINT NOT NULL,
    quarter SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    month_name VARCHAR(12) NOT NULL,
    day_of_month SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL, -- ISO: Monday = 1
    day_name VARCHAR(12) NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

-- Taxi data providers
CREATE TABLE IF NOT EXISTS dwh.dim_vendor (
    vendor_key INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_id SMALLINT NOT NULL UNIQUE
);

-- Payment methods
CREATE TABLE IF NOT EXISTS dwh.dim_payment_type (
    payment_type_key INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_type_id SMALLINT NOT NULL UNIQUE
);

-- TLC pickup/drop-off zones
CREATE TABLE IF NOT EXISTS dwh.dim_location (
    location_key INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_id SMALLINT NOT NULL UNIQUE,
    borough VARCHAR(100),
    zone_name VARCHAR(200),
    service_zone VARCHAR(100)
);

-- One record per source trip
CREATE TABLE IF NOT EXISTS dwh.fact_trips (
    raw_trip_record_id BIGINT PRIMARY KEY,

    pickup_date_key INTEGER REFERENCES dwh.dim_date(date_key),
    dropoff_date_key INTEGER REFERENCES dwh.dim_date(date_key),

    vendor_key INTEGER REFERENCES dwh.dim_vendor(vendor_key),
    payment_type_key INTEGER
        REFERENCES dwh.dim_payment_type(payment_type_key),

    pickup_location_key INTEGER
        REFERENCES dwh.dim_location(location_key),
    dropoff_location_key INTEGER
        REFERENCES dwh.dim_location(location_key),

    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,

    passenger_count SMALLINT,
    trip_distance NUMERIC(8, 2),
    trip_duration_minutes NUMERIC(10, 2),

    fare_amount NUMERIC(8, 2),
    extra NUMERIC(5, 2),
    mta_tax NUMERIC(4, 2),
    tip_amount NUMERIC(7, 2),
    tolls_amount NUMERIC(5, 2),
    improvement_surcharge NUMERIC(4, 2),
    total_amount NUMERIC(9, 2),
    congestion_surcharge NUMERIC(4, 2),
    airport_fee NUMERIC(5, 2),
    cbd_congestion_fee NUMERIC(5, 2),

    is_negative_duration BOOLEAN NOT NULL,
    is_zero_distance BOOLEAN NOT NULL,
    is_negative_fare BOOLEAN NOT NULL,
    is_negative_total BOOLEAN NOT NULL,
    has_missing_critical_fields BOOLEAN NOT NULL,

    loaded_at TIMESTAMPTZ,
    source_file TEXT
);

COMMIT;