CREATE TABLE IF NOT EXISTS raw.vendor_mapping (
    vendor_id SMALLINT PRIMARY KEY,
    vendor_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.ratecode_mapping (
    ratecode_id SMALLINT PRIMARY KEY,
    ratecode_description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.payment_type_mapping (
    payment_type SMALLINT PRIMARY KEY,
    payment_type_description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.taxi_zone_lookup (
    location_id SMALLINT PRIMARY KEY,
    borough TEXT,
    zone TEXT,
    service_zone TEXT
);
