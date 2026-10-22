CREATE TABLE IF NOT EXISTS raw.ingestion_log (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_file     TEXT NOT NULL,
    loaded_at       TIMESTAMPTZ NOT NULL,
    row_count       INTEGER,
    status          VARCHAR(20) NOT NULL
);