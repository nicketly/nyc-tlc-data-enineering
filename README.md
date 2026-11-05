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

## Warehouse pipeline

After raw ingestion has completed, build the staging and dimensional warehouse layers by running these scripts from the project root in the following order:

1. `sql/11_create_dwh_tables.sql` — create the DWH schema, dimensions, and fact table.
2. `sql/10_create_staging_yellow_tripdata.sql` — full-refresh the staging table from raw data and calculate trip duration and data-quality flags. The raw layer remains unchanged.
3. `sql/13_enrich_dwh_dimensions.sql` — add descriptive dimension attributes and the rate-code dimension, including the stable key for missing source rate codes.
4. `sql/12_load_dwh_dimensions.sql` — populate the date, vendor, payment-type, and location dimensions from staging.
5. `sql/14_sync_dwh_reference_dimensions.sql` — synchronize descriptive reference values.
6. `sql/15_load_fact_trips.sql` — load the fact table from staging, resolve dimension keys, and update existing records on conflict.

The staging layer is the single place where trip duration and quality flags are calculated. The fact load reuses those transformed values rather than recalculating them.

## Analytics and data-quality checks

After the warehouse load, run the read-only analytical and monitoring scripts as needed:

- `sql/16_analytics_revenue_and_demand.sql` — revenue and demand analysis.
- `sql/17_data_quality_monitoring.sql` — detailed data-quality diagnostics.
- `sql/18_quality_summary.sql` — compact quality summary.
- `sql/19_investigate_quality_anomalies.sql` — focused anomaly investigation.
- `sql/20_validate_pipeline_integrity.sql` — end-to-end integrity report across raw, staging, and fact tables.

For a healthy run, the integrity report should show equal row counts and distinct-ID counts across the three layers; zero missing or unexpected records; zero staging-to-fact mismatches; and zero missing dimension keys. The report is read-only and can be rerun after each pipeline load.

### Latest validation baseline

For the currently loaded January–February 2026 dataset:

- Raw, staging, and fact tables each contain **7,124,755 rows**.
- Distinct record IDs equal the row count in all three layers.
- No records are missing between layers or unexpectedly present in downstream layers.
- All **7,124,755** staging records match a fact record.
- No duration, quality-flag, or selected source-value mismatches were detected.
- No missing date, vendor, payment-type, rate-code, or location dimension keys were detected.

These are results for the current dataset, not permanent guarantees. Rerun the validation script after new data is ingested.
