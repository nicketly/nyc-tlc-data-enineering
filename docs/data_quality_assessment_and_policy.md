# Data Quality Assessment and Treatment Policy

## Scope

This policy describes how the project treats anomalies observed in the January and February 2026 NYC TLC Yellow Taxi source files loaded into PostgreSQL. It is based on the current profiling results; it is not a claim that every flagged record is erroneous.

## Principles

1. Preserve source records in the raw layer. Do not delete records solely because a quality check flags them.
2. Keep anomaly flags visible in the warehouse so analytical queries can choose a treatment appropriate to the metric.
3. Separate structural integrity checks from business-data anomalies. Structural failures should be fixed; unusual business values require investigation and documented analytical choices.
4. Do not infer the cause of an anomaly when the available fields do not establish it.

## Observed baseline

The loaded dataset contains 7,124,755 raw records and 7,124,755 fact records, with one fact record per raw record. Current checks report no duplicate fact IDs, no missing raw-to-fact records, no fact records without a raw source record, no rate-code mapping mismatches, no missing critical fields, and no missing dimension keys.

Observed anomaly counts in the current baseline:

| Check | Rows | Share of fact rows | Initial treatment |
|---|---:|---:|---|
| Negative trip duration | 3 | <0.0001% | Exclude from duration-based calculations; retain in raw and fact |
| Negative fare | 66,184 | 0.9289% | Retain and investigate; do not automatically remove from financial aggregates |
| Negative total amount | 67,275 | 0.9442% | Retain and investigate; distinguish reported/net amounts from any separately defined positive-only metric |
| Zero trip distance | 248,988 | 3.4947% | Retain; assess separately for distance-based metrics |
| Missing critical fields | 0 | 0% | No current issue detected |
| Missing dimension keys | 0 | 0% | No current issue detected |

Percentages are based on the 7,124,755 fact rows and the current loaded source files. Recalculate them after each new ingestion.

## Findings from anomaly investigation

### Negative durations

Three records have drop-off timestamps earlier than pickup timestamps. The count is very small relative to the dataset. These records should remain available for auditability but should not contribute to trip-duration averages, duration distributions, or duration-based rates unless a specific analysis explicitly studies the anomaly.

### Negative fares and totals

In the investigated sample, negative fare/total values are concentrated in Vendor 2 (Curb Mobility, LLC), particularly among payment types Dispute, Cash, and No charge. The 20 most extreme sampled records include both unusually long elapsed durations and very short/zero-distance trips, with negative fares as low as -$2,555.20 and negative total amounts as low as -$2,560.20.

The source fields do not establish whether these values represent reversals, adjustments, reporting issues, or another business process. Therefore:
- preserve the original values;
- keep negative-value flags;
- report the prevalence and distribution of negative values;
- avoid silently deleting these records or changing their signs;
- document whether a financial metric includes all reported amounts or intentionally applies a separately justified filter.

### Zero-distance trips

Zero distance occurs in multiple payment types. Many Flex Fare records with zero distance still have positive fares and nontrivial durations, so zero distance alone is not sufficient evidence that a record is invalid. Retain these records. For distance-based metrics, report zero-distance prevalence and consider excluding zero-distance records from the specific denominator when appropriate, while stating that rule explicitly. Do not apply the same exclusion automatically to revenue analysis.

### Extreme elapsed durations

The extreme-negative-amount sample includes records whose pickup-to-drop-off elapsed time exceeds 24 hours. This is a candidate for a separate quality flag and further profiling, not an established universal invalidity threshold. Do not cap or rewrite durations without additional evidence and a documented analytical requirement.

## Recommended analytical conventions

- **Trip counts:** include all loaded records by default; provide a filtered count only when its rule is explicit.
- **Duration metrics:** exclude records with negative duration. Consider a separate sensitivity check for unusually long durations rather than silently capping them.
- **Distance metrics:** report zero-distance records separately; decide explicitly whether they belong in each metric's denominator.
- **Financial metrics:** preserve source amounts. Clearly distinguish sums of all reported total amounts from any alternative metric that excludes selected payment types or negative amounts.
- **Data-quality reporting:** show counts and percentages, preserve flags, and track the baseline after subsequent loads.

## Limitations

The current analysis covers two monthly source files and cannot establish the underlying business reason for negative amounts, zero distances, or extreme durations. The observed vendor concentration is descriptive, not proof that the vendor caused the anomalies. Revisit this policy when more months, official field definitions, or corroborating source documentation become available.
