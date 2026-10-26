BEGIN;

-- Enrich existing dimensions with descriptions from the raw reference tables.
ALTER TABLE dwh.dim_vendor
    ADD COLUMN IF NOT EXISTS vendor_name TEXT;

ALTER TABLE dwh.dim_payment_type
    ADD COLUMN IF NOT EXISTS payment_type_description TEXT;

-- Add a dedicated rate-code dimension for trip pricing categories.
CREATE TABLE IF NOT EXISTS dwh.dim_ratecode (
    ratecode_key INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ratecode_id SMALLINT NOT NULL UNIQUE,
    ratecode_description TEXT
);

COMMIT;
