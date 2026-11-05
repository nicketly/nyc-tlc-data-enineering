"""Run the PostgreSQL warehouse pipeline and enforce its integrity checks.

This runner starts after raw ingestion. It does not ingest Parquet files and
never truncates or modifies the raw layer.
"""
from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv


PROJECT_DIR = Path(__file__).resolve().parent.parent
SQL_DIR = PROJECT_DIR / "sql"

# Keep the dependency order explicit. Staging is a full refresh from raw;
# dimensions must exist before the fact table is loaded.
PIPELINE_STEPS = [
    "11_create_dwh_tables.sql",
    "10_create_staging_yellow_tripdata.sql",
    "13_enrich_dwh_dimensions.sql",
    "12_load_dwh_dimensions.sql",
    "14_sync_dwh_reference_dimensions.sql",
    "15_load_fact_trips.sql",
    "20_validate_pipeline_integrity.sql",
]

ZERO_REQUIRED = [
    "raw_missing_from_staging",
    "staging_without_raw",
    "staging_missing_from_fact",
    "fact_without_staging",
    "duration_mismatches",
    "negative_duration_flag_mismatches",
    "zero_distance_flag_mismatches",
    "negative_fare_flag_mismatches",
    "negative_total_flag_mismatches",
    "missing_field_flag_mismatches",
    "source_value_mismatches",
    "missing_pickup_date_keys",
    "missing_dropoff_date_keys",
    "missing_vendor_keys",
    "missing_payment_type_keys",
    "missing_ratecode_keys",
    "missing_pickup_location_keys",
    "missing_dropoff_location_keys",
]


def get_connection() -> psycopg.Connection:
    """Create a database connection from the project's .env settings."""
    load_dotenv(PROJECT_DIR / ".env")
    required = [
        "DATABASE_NAME",
        "DATABASE_USER",
        "DATABASE_PASSWORD",
        "HOST",
        "PORT",
    ]
    missing = [key for key in required if not os.getenv(key)]
    if missing:
        raise ValueError(
            "Missing environment variables: " + ", ".join(missing)
        )

    return psycopg.connect(
        dbname=os.environ["DATABASE_NAME"],
        user=os.environ["DATABASE_USER"],
        password=os.environ["DATABASE_PASSWORD"],
        host=os.environ["HOST"],
        port=os.environ["PORT"],
    )


def run_sql_file(conn: psycopg.Connection, filename: str) -> None:
    """Execute one SQL file as a unit and fail immediately on SQL errors."""
    path = SQL_DIR / filename
    if not path.is_file():
        raise FileNotFoundError(f"SQL file not found: {path}")

    sql = path.read_text(encoding="utf-8")
    logging.info("Running %s", filename)

    # prepare=False uses PostgreSQL's simple-query protocol, allowing the
    # transaction statements included in the project's SQL scripts.
    with conn.cursor() as cur:
        cur.execute(sql, prepare=False)


def validate_integrity(conn: psycopg.Connection) -> None:
    """Run the integrity report and raise if any required check fails."""
    with conn.cursor() as cur:
        cur.execute(
            (SQL_DIR / "20_validate_pipeline_integrity.sql").read_text(
                encoding="utf-8"
            ),
            prepare=False,
        )
        columns = [item.name for item in cur.description]
        values = cur.fetchone()

    if values is None:
        raise RuntimeError("Integrity validation returned no result.")

    report = dict(zip(columns, values))
    logging.info("Integrity report:")
    for name, value in report.items():
        logging.info("  %-40s %s", name, f"{value:,}" if isinstance(value, int) else value)

    failures = []

    # All layers must contain the same number of records, and each ID must
    # be unique within its layer.
    for layer in ("raw", "staging", "fact"):
        rows = report[f"{layer}_rows"]
        distinct_ids = report[f"{layer}_distinct_ids"]
        if rows != distinct_ids:
            failures.append(
                f"{layer}: {rows} rows but {distinct_ids} distinct IDs"
            )

    if not (
        report["raw_rows"]
        == report["staging_rows"]
        == report["fact_rows"]
    ):
        failures.append("Raw, staging, and fact row counts differ.")

    if report["matched_staging_fact_records"] != report["staging_rows"]:
        failures.append(
            "Not every staging record has a matching fact record."
        )

    for metric in ZERO_REQUIRED:
        if report[metric] != 0:
            failures.append(f"{metric} expected 0, got {report[metric]}")

    if failures:
        raise RuntimeError(
            "Pipeline integrity validation failed:\n- "
            + "\n- ".join(failures)
        )

    logging.info("All pipeline integrity checks passed.")


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    try:
        with get_connection() as conn:
            for filename in PIPELINE_STEPS:
                run_sql_file(conn, filename)

            # The validation SQL is read-only. Its result is checked in Python
            # so a non-zero integrity metric makes this process exit non-zero.
            validate_integrity(conn)

        logging.info("Warehouse pipeline completed successfully.")
        return 0

    except Exception:
        logging.exception("Warehouse pipeline failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
