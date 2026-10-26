BEGIN;

-- 1. Synchronize vendor IDs and human-readable names.
INSERT INTO dwh.dim_vendor (vendor_id, vendor_name)
SELECT DISTINCT
    s.vendor_id,
    m.vendor_name
FROM staging.yellow_tripdata AS s
LEFT JOIN raw.vendor_mapping AS m
    ON m.vendor_id = s.vendor_id
WHERE s.vendor_id IS NOT NULL
ON CONFLICT (vendor_id) DO UPDATE
SET vendor_name = EXCLUDED.vendor_name
WHERE dwh.dim_vendor.vendor_name IS DISTINCT FROM EXCLUDED.vendor_name;


-- 2. Synchronize payment types and their descriptions.
INSERT INTO dwh.dim_payment_type (payment_type_id, payment_type_description)
SELECT DISTINCT
    s.payment_type,
    m.payment_type_description
FROM staging.yellow_tripdata AS s
LEFT JOIN raw.payment_type_mapping AS m
    ON m.payment_type = s.payment_type
WHERE s.payment_type IS NOT NULL
ON CONFLICT (payment_type_id) DO UPDATE
SET payment_type_description = EXCLUDED.payment_type_description
WHERE dwh.dim_payment_type.payment_type_description
    IS DISTINCT FROM EXCLUDED.payment_type_description;


-- 3. Synchronize all pickup/drop-off locations and descriptive zone attributes.
INSERT INTO dwh.dim_location (
    location_id,
    borough,
    zone_name,
    service_zone
)
SELECT DISTINCT
    locations.location_id,
    z.borough,
    z.zone,
    z.service_zone
FROM (
    SELECT pickup_location_id AS location_id
    FROM staging.yellow_tripdata
    WHERE pickup_location_id IS NOT NULL

    UNION

    SELECT dropoff_location_id AS location_id
    FROM staging.yellow_tripdata
    WHERE dropoff_location_id IS NOT NULL
) AS locations
LEFT JOIN raw.taxi_zone_lookup AS z
    ON z.location_id = locations.location_id
ON CONFLICT (location_id) DO UPDATE
SET
    borough = EXCLUDED.borough,
    zone_name = EXCLUDED.zone_name,
    service_zone = EXCLUDED.service_zone
WHERE (dwh.dim_location.borough,
       dwh.dim_location.zone_name,
       dwh.dim_location.service_zone)
    IS DISTINCT FROM
      (EXCLUDED.borough,
       EXCLUDED.zone_name,
       EXCLUDED.service_zone);


-- 4. Populate a rate-code dimension using codes observed in staging.
INSERT INTO dwh.dim_ratecode (ratecode_id, ratecode_description)
SELECT DISTINCT
    s.ratecode_id,
    r.ratecode_description
FROM staging.yellow_tripdata AS s
LEFT JOIN raw.ratecode_mapping AS r
    ON r.ratecode_id = s.ratecode_id
WHERE s.ratecode_id IS NOT NULL
ON CONFLICT (ratecode_id) DO UPDATE
SET ratecode_description = EXCLUDED.ratecode_description
WHERE dwh.dim_ratecode.ratecode_description
    IS DISTINCT FROM EXCLUDED.ratecode_description;

COMMIT;
