import csv
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import psycopg
import pyarrow.parquet as pq
from dotenv import load_dotenv


PROJECT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_DIR / "data"
RECORDS_DIR = DATA_DIR / "records"
REFERENCE_DIR = DATA_DIR / "reference"
MAPPINGS_PATH = REFERENCE_DIR / "code_mappings.json"
ZONE_LOOKUP_PATH = REFERENCE_DIR / "taxi_zone_lookup.csv"

load_dotenv(PROJECT_DIR / ".env")

# Required fields define a usable trip record. Other source columns may be
# absent in older/newer monthly extracts and are loaded as SQL NULL.
REQUIRED_COLUMNS = {
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "trip_distance",
    "fare_amount",
    "total_amount",
}

SOURCE_COLUMNS = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "passenger_count",
    "trip_distance",
    "RatecodeID",
    "store_and_fwd_flag",
    "PULocationID",
    "DOLocationID",
    "payment_type",
    "fare_amount",
    "extra",
    "mta_tax",
    "tip_amount",
    "tolls_amount",
    "improvement_surcharge",
    "total_amount",
    "congestion_surcharge",
    "Airport_fee",
    "cbd_congestion_fee",
]

COLUMNS = SOURCE_COLUMNS + ["loaded_at", "source_file"]

INTEGER_COLUMNS = [
    "VendorID", "passenger_count", "RatecodeID", "PULocationID",
    "DOLocationID", "payment_type",
]
NUMERIC_COLUMNS = [
    "trip_distance", "fare_amount", "extra", "mta_tax", "tip_amount",
    "tolls_amount", "improvement_surcharge", "total_amount",
    "congestion_surcharge", "Airport_fee", "cbd_congestion_fee",
]
DATETIME_COLUMNS = ["tpep_pickup_datetime", "tpep_dropoff_datetime"]

COPY_SQL = """
    COPY raw.yellow_tripdata (
        VendorID, tpep_pickup_datetime, tpep_dropoff_datetime,
        passenger_count, trip_distance, RatecodeID, store_and_fwd_flag,
        PULocationID, DOLocationID, payment_type, fare_amount, extra,
        mta_tax, tip_amount, tolls_amount, improvement_surcharge,
        total_amount, congestion_surcharge, Airport_fee, cbd_congestion_fee,
        loaded_at, source_file
    ) FROM STDIN
"""


def get_connection():
    required = [
        "DATABASE_NAME", "DATABASE_USER", "DATABASE_PASSWORD", "HOST", "PORT"
    ]
    missing = [key for key in required if not os.getenv(key)]
    if missing:
        raise ValueError(f"Missing environment variables: {', '.join(missing)}")

    return psycopg.connect(
        dbname=os.environ["DATABASE_NAME"],
        user=os.environ["DATABASE_USER"],
        password=os.environ["DATABASE_PASSWORD"],
        host=os.environ["HOST"],
        port=os.environ["PORT"],
    )


def is_already_loaded(conn, source_file):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT EXISTS (
                SELECT 1 FROM raw.ingestion_log
                WHERE source_file = %s AND status = 'success'
            );
            """,
            (source_file,),
        )
        return cur.fetchone()[0]


def load_reference_data(conn):
    """Upsert reference records so reruns are safe and corrections propagate."""
    if not MAPPINGS_PATH.is_file():
        raise FileNotFoundError(f"Code mappings not found: {MAPPINGS_PATH}")
    if not ZONE_LOOKUP_PATH.is_file():
        raise FileNotFoundError(f"Taxi zone lookup not found: {ZONE_LOOKUP_PATH}")

    with MAPPINGS_PATH.open("r", encoding="utf-8") as f:
        mappings = json.load(f)

    with conn.cursor() as cur:
        for raw_id, description in mappings.get("VendorID", {}).items():
            cur.execute(
                """
                INSERT INTO raw.vendor_mapping (vendor_id, vendor_name)
                VALUES (%s, %s)
                ON CONFLICT (vendor_id) DO UPDATE
                SET vendor_name = EXCLUDED.vendor_name;
                """,
                (int(raw_id), description),
            )

        for raw_id, description in mappings.get("RatecodeID", {}).items():
            cur.execute(
                """
                INSERT INTO raw.ratecode_mapping (ratecode_id, ratecode_description)
                VALUES (%s, %s)
                ON CONFLICT (ratecode_id) DO UPDATE
                SET ratecode_description = EXCLUDED.ratecode_description;
                """,
                (int(raw_id), description),
            )

        for raw_id, description in mappings.get("payment_type", {}).items():
            cur.execute(
                """
                INSERT INTO raw.payment_type_mapping (payment_type, payment_type_description)
                VALUES (%s, %s)
                ON CONFLICT (payment_type) DO UPDATE
                SET payment_type_description = EXCLUDED.payment_type_description;
                """,
                (int(raw_id), description),
            )

        with ZONE_LOOKUP_PATH.open("r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            expected = {"LocationID", "Borough", "Zone", "service_zone"}
            if not reader.fieldnames or not expected.issubset(reader.fieldnames):
                raise ValueError(
                    "Taxi zone CSV must contain columns: "
                    + ", ".join(sorted(expected))
                )

            for row in reader:
                cur.execute(
                    """
                    INSERT INTO raw.taxi_zone_lookup
                        (location_id, borough, zone, service_zone)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (location_id) DO UPDATE
                    SET borough = EXCLUDED.borough,
                        zone = EXCLUDED.zone,
                        service_zone = EXCLUDED.service_zone;
                    """,
                    (
                        int(row["LocationID"]),
                        row["Borough"] or None,
                        row["Zone"] or None,
                        row["service_zone"] or None,
                    ),
                )


def normalize_batch(df, loaded_at, source_file):
    df = df.copy()

    for column in SOURCE_COLUMNS:
        if column not in df.columns:
            if column in REQUIRED_COLUMNS:
                raise ValueError(f"Required column missing: {column}")
            df[column] = pd.NA

    df["loaded_at"] = loaded_at
    df["source_file"] = source_file
    df = df[COLUMNS]

    for column in INTEGER_COLUMNS:
        df[column] = pd.to_numeric(df[column], errors="raise").astype("Int16")

    for column in NUMERIC_COLUMNS:
        df[column] = pd.to_numeric(df[column], errors="raise").round(2)

    df["store_and_fwd_flag"] = df["store_and_fwd_flag"].astype("string")

    for column in DATETIME_COLUMNS:
        df[column] = pd.to_datetime(df[column], errors="raise")

    # psycopg accepts Python None for SQL NULL, not pandas' NA/NaT sentinels.
    return df.astype(object).where(pd.notna(df), None)


def load_parquet(conn, file_path, loaded_at, batch_size=100_000):
    parquet_file = pq.ParquetFile(file_path)
    available_columns = set(parquet_file.schema_arrow.names)
    missing_required = REQUIRED_COLUMNS - available_columns
    if missing_required:
        raise ValueError(
            f"{file_path.name} is missing required columns: "
            f"{sorted(missing_required)}"
        )

    row_count = 0
    # Called inside a connection transaction: any batch failure rolls back
    # the complete monthly file rather than leaving partial trip rows.
    with conn.cursor() as cur:
        for batch in parquet_file.iter_batches(
            batch_size=batch_size,
            columns=[c for c in SOURCE_COLUMNS if c in available_columns],
        ):
            df = normalize_batch(batch.to_pandas(), loaded_at, file_path.name)
            with cur.copy(COPY_SQL) as copy:
                for row in df.itertuples(index=False, name=None):
                    copy.write_row(row)
            row_count += len(df)

    return row_count


def log_success(conn, source_file, loaded_at, row_count):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO raw.ingestion_log
                (source_file, loaded_at, row_count, status)
            VALUES (%s, %s, %s, 'success');
            """,
            (source_file, loaded_at, row_count),
        )


def log_failure(source_file, loaded_at, error_message):
    # This uses a separate transaction so a failed file's rollback does not
    # remove its failure record.
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO raw.ingestion_log
                    (source_file, loaded_at, row_count, status)
                VALUES (%s, %s, NULL, 'failed');
                """,
                (source_file, loaded_at),
            )
    print(f"Failed to load {source_file}: {error_message}")


def main():
    if not RECORDS_DIR.is_dir():
        raise FileNotFoundError(f"Records directory not found: {RECORDS_DIR}")

    parquet_files = sorted(RECORDS_DIR.glob("yellow_tripdata_*.parquet"))
    if not parquet_files:
        raise FileNotFoundError(
            f"No monthly Parquet files found in {RECORDS_DIR}"
        )

    # Reference data is loaded first and committed as one transaction.
    with get_connection() as conn:
        load_reference_data(conn)

    for file_path in parquet_files:
        source_file = file_path.name
        loaded_at = datetime.now(timezone.utc)

        try:
            with get_connection() as conn:
                if is_already_loaded(conn, source_file):
                    print(f"File already loaded: {source_file}")
                    continue

                row_count = load_parquet(conn, file_path, loaded_at)
                log_success(conn, source_file, loaded_at, row_count)

            print(f"Successfully loaded {row_count:,} rows from {source_file}")

        except Exception as exc:
            try:
                log_failure(source_file, loaded_at, str(exc))
            except Exception as log_error:
                print(f"Could not record ingestion failure for {source_file}: {log_error}")
            raise


if __name__ == "__main__":
    main()
