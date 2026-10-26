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

-- Stable dimension member for trips whose source RatecodeID is NULL.
-- Key 0 is reserved so missing source values can still have a valid FK.
INSERT INTO dwh.dim_ratecode (
    ratecode_key,
    ratecode_id,
    ratecode_description
)
OVERRIDING SYSTEM VALUE
VALUES (0, 0, 'Null/missing')
ON CONFLICT (ratecode_id) DO UPDATE
SET ratecode_description = EXCLUDED.ratecode_description
WHERE dwh.dim_ratecode.ratecode_description
    IS DISTINCT FROM EXCLUDED.ratecode_description;

COMMIT;
