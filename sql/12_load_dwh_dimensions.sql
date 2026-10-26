
BEGIN;

-- 1. Calendar dimension
INSERT INTO dwh.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend
)
SELECT
    TO_CHAR(d::DATE, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d)::SMALLINT,
    EXTRACT(QUARTER FROM d)::SMALLINT,
    EXTRACT(MONTH FROM d)::SMALLINT,
    TO_CHAR(d, 'FMMonth'),
    EXTRACT(DAY FROM d)::SMALLINT,
    EXTRACT(ISODOW FROM d)::SMALLINT,
    TO_CHAR(d, 'FMDay'),
    EXTRACT(ISODOW FROM d) IN (6, 7)
FROM (
    SELECT DISTINCT pickup_datetime::DATE AS d
    FROM staging.yellow_tripdata
    WHERE pickup_datetime IS NOT NULL

    UNION

    SELECT DISTINCT dropoff_datetime::DATE AS d
    FROM staging.yellow_tripdata
    WHERE dropoff_datetime IS NOT NULL
) AS dates
ON CONFLICT (date_key) DO NOTHING;


-- 2. Vendor dimension
INSERT INTO dwh.dim_vendor (vendor_id)
SELECT DISTINCT vendor_id
FROM staging.yellow_tripdata
WHERE vendor_id IS NOT NULL
ON CONFLICT (vendor_id) DO NOTHING;


-- 3. Payment type dimension
INSERT INTO dwh.dim_payment_type (payment_type_id)
SELECT DISTINCT payment_type
FROM staging.yellow_tripdata
WHERE payment_type IS NOT NULL
ON CONFLICT (payment_type_id) DO NOTHING;


-- 4. Location dimension
INSERT INTO dwh.dim_location (location_id)
SELECT DISTINCT location_id
FROM (
    SELECT pickup_location_id AS location_id
    FROM staging.yellow_tripdata
    WHERE pickup_location_id IS NOT NULL

    UNION

    SELECT dropoff_location_id AS location_id
    FROM staging.yellow_tripdata
    WHERE dropoff_location_id IS NOT NULL
) AS locations
ON CONFLICT (location_id) DO NOTHING;

COMMIT;