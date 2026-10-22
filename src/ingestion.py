import psycopg
from pathlib import Path
import pandas as pd
from datetime import datetime, timezone

CURRENT_DIR = Path.cwd()
DATA_DIR = CURRENT_DIR / "data"

def get_connection():
    conn = psycopg.connect(
        dbname = 'yellow_tripdata_DB',
        user = 'postgres',
        password = '***REMOVED***',
        host = 'localhost',
        port = '5432'
    )

    return conn


def is_already_loaded(conn, source_file):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT 1
            FROM raw.ingestion_log
            WHERE source_file = %s
              AND status = 'success';
            """,
            (source_file,)
        )

        result = cur.fetchone()

        return result is not None

def normalize_types(df):
    # Integer columns
    integer_columns = [
        "VendorID",
        "passenger_count",
        "RatecodeID",
        "PULocationID",
        "DOLocationID",
        "payment_type"
    ]

    for column in integer_columns:
        df[column] = df[column].astype("Int16")

    # Numeric columns
    numeric_columns = [
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
        "cbd_congestion_fee"
    ]

    for column in numeric_columns:
        df[column] = df[column].round(2)

    # String columns
    df["store_and_fwd_flag"] = df["store_and_fwd_flag"].astype("string")

    # Datetime columns
    datetime_columns = [
        "tpep_pickup_datetime",
        "tpep_dropoff_datetime"
    ]

    for column in datetime_columns:
        df[column] = pd.to_datetime(df[column])

    return df

def load_parquet(conn, file_path):
    df = pd.read_parquet(file_path)

    loaded_at = datetime.now(timezone.utc)
    source_file = file_path.name.split("/")[-1]

    df["loaded_at"] = loaded_at
    df["source_file"] = source_file

    columns = [
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
        "source_file"
    ]

    df = df[columns]
    df = normalize_types(df)

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

            for row in df.head(5).itertuples(index=False, name=None):
                copy.write_row(row)

    conn.commit()

    return 5

def log_success(conn, source_file, loaded_at, row_count):
    ...

def main():
    conn = get_connection()
    file_path = DATA_DIR / "yellow_tripdata_2026-01.parquet"
    source_file = file_path.name

    if is_already_loaded(conn, source_file):
        print("File already loaded")
        conn.close()
        return

    load_parquet(conn, file_path)

    conn.close()

if __name__ == "__main__":
    main()