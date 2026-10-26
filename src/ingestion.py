
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv


PROJECT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_DIR / "data"

load_dotenv(PROJECT_DIR / ".env")

COLUMNS = [
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
    "loaded_at",
    "source_file",
]

INTEGER_COLUMNS = [
    "VendorID",
    "passenger_count",
    "RatecodeID",
    "PULocationID",
    "DOLocationID",
    "payment_type",
]

NUMERIC_COLUMNS = [
    "trip_distance",
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

DATETIME_COLUMNS = [
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
]


def get_connection():
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
            f"Missing environment variables: {', '.join(missing)}"
        )

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
                SELECT 1
                FROM raw.ingestion_log
                WHERE source_file = %s
                  AND status = 'success'
            );
            """,
            (source_file,),
        )
        return cur.fetchone()[0]


def normalize_types(df):
    df = df.copy()

    for column in INTEGER_COLUMNS:
        df[column] = df[column].astype("Int16")

    for column in NUMERIC_COLUMNS:
        df[column] = pd.to_numeric(df[column], errors="raise").round(2)

    df["store_and_fwd_flag"] = df["store_and_fwd_flag"].astype("string")

    for column in DATETIME_COLUMNS:
        df[column] = pd.to_datetime(df[column], errors="raise")

    # Convert pandas missing values (pd.NA, NaN, NaT) to Python None,
    # which psycopg can insert as SQL NULL
    df = df.astype(object).where(pd.notna(df), None)

    return df


def load_parquet(conn, file_path, loaded_at):
    df = pd.read_parquet(file_path)

    missing_columns = set(COLUMNS) - {
        "loaded_at",
        "source_file",
    } - set(df.columns)

    if missing_columns:
        raise ValueError(
            f"Parquet file is missing columns: {sorted(missing_columns)}"
        )

    df["loaded_at"] = loaded_at
    df["source_file"] = file_path.name
    df = normalize_types(df[COLUMNS])

    with conn.cursor() as cur:
        with cur.copy(
            """
            COPY raw.yellow_tripdata (
                VendorID,
                tpep_pickup_datetime,
                tpep_dropoff_datetime,
                passenger_count,
                trip_distance,
                RatecodeID,
                store_and_fwd_flag,
                PULocationID,
                DOLocationID,
                payment_type,
                fare_amount,
                extra,
                mta_tax,
                tip_amount,
                tolls_amount,
                improvement_surcharge,
                total_amount,
                congestion_surcharge,
                Airport_fee,
                cbd_congestion_fee,
                loaded_at,
                source_file
            )
            FROM STDIN
            """
        ) as copy:
            for row in df.itertuples(index=False, name=None):
                copy.write_row(row)

    return len(df)


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


def log_failure(source_file, loaded_at):
    # Use a separate transaction so a failed data load can be rolled back
    # without also losing its failure record.
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


def main():
    file_path = DATA_DIR / "yellow_tripdata_2026-01.parquet"

    if not file_path.is_file():
        raise FileNotFoundError(f"Parquet file not found: {file_path}")

    source_file = file_path.name
    loaded_at = datetime.now(timezone.utc)

    try:
        # The connection context commits on success and rolls back on error
        # It also closes the connection
        with get_connection() as conn:
            if is_already_loaded(conn, source_file):
                print(f"File already loaded: {source_file}")
                return

            row_count = load_parquet(conn, file_path, loaded_at)
            log_success(conn, source_file, loaded_at, row_count)

        print(f"Successfully loaded {row_count:,} rows from {source_file}")

    except Exception:
        try:
            log_failure(source_file, loaded_at)
        except Exception as log_error:
            print(f"Could not record ingestion failure: {log_error}")

        raise


if __name__ == "__main__":
    main()
