-- Analytical queries for business-facing insights.
-- Source: dwh.fact_trips and conformed dimensions.
-- These are read-only queries; they do not modify warehouse data.

-- 1. Monthly trip volume and revenue trend.
-- Revenue is based on the source total_amount and includes negative amounts.
SELECT
    d.year,
    d.month,
    d.month_name,
    COUNT(*) AS trip_count,
    ROUND(SUM(f.total_amount), 2) AS total_revenue,
    ROUND(AVG(f.total_amount), 2) AS average_amount_per_trip,
    ROUND(AVG(f.trip_distance), 2) AS average_trip_distance_miles,
    ROUND(AVG(f.trip_duration_minutes), 2) AS average_trip_duration_minutes
FROM dwh.fact_trips AS f
JOIN dwh.dim_date AS d
    ON d.date_key = f.pickup_date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- 2. Demand and revenue by pickup hour.
-- Useful for identifying busy periods; hour is taken from local pickup timestamp.
SELECT
    EXTRACT(HOUR FROM pickup_datetime)::INTEGER AS pickup_hour,
    COUNT(*) AS trip_count,
    ROUND(SUM(total_amount), 2) AS total_revenue,
    ROUND(AVG(total_amount), 2) AS average_amount_per_trip,
    ROUND(AVG(trip_duration_minutes), 2) AS average_trip_duration_minutes
FROM dwh.fact_trips
WHERE pickup_datetime IS NOT NULL
GROUP BY EXTRACT(HOUR FROM pickup_datetime)::INTEGER
ORDER BY pickup_hour;


-- 3. Pickup demand and revenue by borough.
-- Location records without a borough are retained as 'Unknown / not mapped'.
SELECT
    COALESCE(l.borough, 'Unknown / not mapped') AS pickup_borough,
    COUNT(*) AS trip_count,
    ROUND(SUM(f.total_amount), 2) AS total_revenue,
    ROUND(AVG(f.total_amount), 2) AS average_amount_per_trip,
    ROUND(AVG(f.trip_distance), 2) AS average_trip_distance_miles
FROM dwh.fact_trips AS f
LEFT JOIN dwh.dim_location AS l
    ON l.location_key = f.pickup_location_key
GROUP BY COALESCE(l.borough, 'Unknown / not mapped')
ORDER BY trip_count DESC;


-- 4. Trip volume and tips by payment type.
SELECT
    COALESCE(p.payment_type_description, 'Unknown / not mapped') AS payment_type,
    COUNT(*) AS trip_count,
    ROUND(SUM(f.total_amount), 2) AS total_revenue,
    ROUND(AVG(f.tip_amount), 2) AS average_tip_amount,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE COALESCE(f.tip_amount, 0) > 0)
        / NULLIF(COUNT(*), 0),
        2
    ) AS trips_with_positive_tip_pct
FROM dwh.fact_trips AS f
LEFT JOIN dwh.dim_payment_type AS p
    ON p.payment_type_key = f.payment_type_key
GROUP BY COALESCE(p.payment_type_description, 'Unknown / not mapped')
ORDER BY trip_count DESC;
