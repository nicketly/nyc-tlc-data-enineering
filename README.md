# NYC TLC Yellow Taxi Data Engineering

A portfolio project for ingesting NYC TLC Yellow Taxi trip data into PostgreSQL, validating raw data, transforming it into a dimensional model, and building analytical outputs.

## Ingestion layout

Place monthly trip Parquet files in `data/records/` using names such as `yellow_tripdata_2026-01.parquet`.

Reference files belong in `data/reference/`:

- `code_mappings.json`
- `taxi_zone_lookup.csv`

The ingestion script loads reference data with upserts, discovers all matching monthly Parquet files, and skips files already recorded as successfully loaded. It processes each Parquet file in batches, but commits or rolls back that file as a single transaction.

## Setup

1. Create and activate a virtual environment.
2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Create a local `.env` file with these variables:

   ```dotenv
   DATABASE_NAME=your_database
   DATABASE_USER=your_user
   DATABASE_PASSWORD=your_password
   HOST=localhost
   PORT=5432
   ```

4. Run the SQL scripts in order, from the project root:

   - `sql/01_create_schemas.sql`
   - `sql/02_create_raw_yellow_tripdata.sql`
   - `sql/03_create_ingestion_log.sql`
   - `sql/04_create_index_ingestion_log.sql`
   - `sql/05_create_raw_reference_tables.sql`

   Ensure the `raw`, `staging`, and `dwh` schemas and the raw trip/log tables exist before running ingestion.

5. Run ingestion from the project root:

   ```bash
   python src/ingestion.py
   ```

## Ingestion behavior

- Reference tables are idempotently upserted on every run.
- Files matching `data/records/yellow_tripdata_*.parquet` are processed in filename order.
- Successfully loaded files are skipped on later runs.
- Missing optional source columns are represented as SQL `NULL`.
- Missing required fields or a batch load error causes the current file transaction to roll back. A failure log entry is then written separately.
- A success log entry is written only in the same transaction as the complete file load.

Do not commit database credentials or the local `.env` file.
