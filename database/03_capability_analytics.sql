-- 1. Latest benchmark coverage
WITH latest_models AS (
    SELECT
        model_id,
        COALESCE(NULLIF(canonical_slug, ''), model_id) AS benchmark_key
    FROM fact_model_snapshot
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)),
latest_benchmark_keys AS (
    SELECT DISTINCT model_key
    FROM fact_benchmark_snapshot
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot))
SELECT
    COUNT(*) AS latest_models,
    COUNT(b.model_key) AS models_with_benchmark,
    COUNT(*) - COUNT(b.model_key) AS models_without_benchmark,
    ROUND(100.0 * COUNT(b.model_key) / COUNT(*), 2) AS benchmark_coverage_pct
FROM latest_models m
LEFT JOIN latest_benchmark_keys b ON m.benchmark_key = b.model_key;

-- 2. Latest capability coverage and distribution
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT
            b.*,
            ROW_NUMBER() OVER (
                PARTITION BY b.model_key
                ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id
            ) AS rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
    ) ranked
    WHERE rn = 1
)
SELECT
    COUNT(*) AS latest_benchmark_keys,
    COUNT(intelligence_index) AS intelligence_coverage,
    COUNT(coding_index) AS coding_coverage,
    COUNT(agentic_index) AS agentic_coverage,
    ROUND(AVG(intelligence_index), 2) AS avg_intelligence_index,
    ROUND(AVG(coding_index), 2) AS avg_coding_index,
    ROUND(AVG(agentic_index), 2) AS avg_agentic_index,
    ROUND(MIN(intelligence_index), 2) AS min_intelligence_index,
    ROUND(MAX(intelligence_index), 2) AS max_intelligence_index,
    ROUND(MIN(coding_index), 2) AS min_coding_index,
    ROUND(MAX(coding_index), 2) AS max_coding_index,
    ROUND(MIN(agentic_index), 2) AS min_agentic_index,
    ROUND(MAX(agentic_index), 2) AS max_agentic_index
FROM latest_benchmarks;

-- 3. Benchmark records by source
SELECT
    source,
    COUNT(*) AS benchmark_records,
    COUNT(DISTINCT model_key) AS models_covered
FROM fact_benchmark_snapshot
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
GROUP BY source
ORDER BY models_covered DESC, benchmark_records DESC;


-- 4. Top models by capability index 
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT
            b.*,
            ROW_NUMBER() OVER (
                PARTITION BY b.model_key
                ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id
            ) AS rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
    ) ranked
    WHERE rn = 1),
unique_models AS (
    SELECT
        model_id,
        model_name,
        model_creator,
        benchmark_key
    FROM (
        SELECT
            f.model_id,
            d.model_name,
            REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
            COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) AS benchmark_key,
            ROW_NUMBER() OVER (
                PARTITION BY REGEXP_REPLACE(f.model_id, ':(batch|free)$', '')
                ORDER BY 
                    CASE
                        WHEN f.model_id LIKE '%:batch' THEN 2
                        WHEN f.model_id LIKE '%:free' THEN 3
                        ELSE 1
                    END,
                    f.model_id) AS rn
        FROM fact_model_snapshot f
        JOIN dim_model d ON f.model_id = d.model_id
        WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
    ) ranked_models
    WHERE rn = 1),
model_capability AS (
    SELECT
        m.model_id,
        m.model_name,
        m.model_creator,
        b.intelligence_index,
        b.coding_index,
        b.agentic_index
    FROM unique_models m
    JOIN latest_benchmarks b ON m.benchmark_key = b.model_key),
ranked_capabilities AS (
    SELECT
        capability_metric,
        model_id,
        model_name,
        model_creator,
        capability_score,
        RANK() OVER (PARTITION BY capability_metric ORDER BY capability_score DESC) AS capability_rank
    FROM (
        SELECT 'Intelligence Index' AS capability_metric, model_id, model_name, model_creator, intelligence_index AS capability_score 
        FROM model_capability WHERE intelligence_index IS NOT NULL
        UNION ALL
        SELECT 'Coding Index' AS capability_metric, model_id, model_name, model_creator, coding_index AS capability_score 
        FROM model_capability WHERE coding_index IS NOT NULL
        UNION ALL
        SELECT 'Agentic Index' AS capability_metric, model_id, model_name, model_creator, agentic_index AS capability_score 
        FROM model_capability WHERE agentic_index IS NOT NULL
    ) unpivoted)
SELECT
    capability_metric,
    model_id,
    model_name,
    model_creator,
    ROUND(capability_score, 2) AS capability_score,
    capability_rank
FROM ranked_capabilities
WHERE capability_rank <= 15
ORDER BY capability_metric, capability_rank, model_id;

-- 5. Capability aggregates by creator
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT
            b.*,
            ROW_NUMBER() OVER (
                PARTITION BY b.model_key
                ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id
            ) AS rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
    ) ranked
    WHERE rn = 1
),
current_models AS (
    SELECT
        f.model_id,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) AS benchmark_key
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
)
SELECT
    m.model_creator,
    COUNT(DISTINCT m.model_id) AS benchmarked_models,
    ROUND(AVG(b.intelligence_index), 2) AS avg_intelligence_index,
    ROUND(AVG(b.coding_index), 2) AS avg_coding_index,
    ROUND(AVG(b.agentic_index), 2) AS avg_agentic_index
FROM current_models m
JOIN latest_benchmarks b ON m.benchmark_key = b.model_key
GROUP BY m.model_creator
ORDER BY benchmarked_models DESC;

-- 6. Benchmark score shifts between two latest snapshots
WITH ranked_benchmarks AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY b.snapshot_date, b.model_key, b.source
            ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id
        ) AS rn
    FROM fact_benchmark_snapshot b),
latest_two_dates AS (
    SELECT DISTINCT snapshot_date
    FROM fact_benchmark_snapshot
    ORDER BY snapshot_date DESC
    LIMIT 2), benchmark_history AS (
    SELECT
        b.snapshot_date,
        b.source,
        b.model_key,
        b.intelligence_index,
        b.coding_index,
        b.agentic_index
    FROM ranked_benchmarks b
    JOIN latest_two_dates d ON b.snapshot_date = d.snapshot_date
    WHERE b.rn = 1),
benchmark_changes AS (
    SELECT
        curr.snapshot_date,
        curr.source,
        curr.model_key,
        prev.intelligence_index AS previous_intelligence_index,
        curr.intelligence_index AS current_intelligence_index,
        prev.coding_index AS previous_coding_index,
        curr.coding_index AS current_coding_index,
        prev.agentic_index AS previous_agentic_index,
        curr.agentic_index AS current_agentic_index
    FROM benchmark_history curr
    JOIN benchmark_history prev 
      ON curr.model_key = prev.model_key
     AND curr.source = prev.source
     AND curr.snapshot_date > prev.snapshot_date
)
SELECT
    snapshot_date,
    source,
    model_key,
    ROUND(previous_intelligence_index, 2) AS previous_intelligence_index,
    ROUND(current_intelligence_index, 2) AS current_intelligence_index,
    ROUND(current_intelligence_index - previous_intelligence_index, 2) AS intelligence_change,
    ROUND(previous_coding_index, 2) AS previous_coding_index,
    ROUND(current_coding_index, 2) AS current_coding_index,
    ROUND(current_coding_index - previous_coding_index, 2) AS coding_change,
    ROUND(previous_agentic_index, 2) AS previous_agentic_index,
    ROUND(current_agentic_index, 2) AS current_agentic_index,
    ROUND(current_agentic_index - previous_agentic_index, 2) AS agentic_change
FROM benchmark_changes
WHERE current_intelligence_index IS DISTINCT FROM previous_intelligence_index
   OR current_coding_index IS DISTINCT FROM previous_coding_index
   OR current_agentic_index IS DISTINCT FROM previous_agentic_index
ORDER BY (
    ABS(COALESCE(current_intelligence_index - previous_intelligence_index, 0)) +
    ABS(COALESCE(current_coding_index - previous_coding_index, 0)) +
    ABS(COALESCE(current_agentic_index - previous_agentic_index, 0))
) DESC;

-- 7. Benchmark coverage gaps by creator (Anti-join)
WITH latest_models AS (
    SELECT
        f.model_id,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) AS benchmark_key
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
),
latest_benchmark_keys AS (
    SELECT DISTINCT model_key
    FROM fact_benchmark_snapshot
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
)
SELECT
    m.model_creator,
    COUNT(*) AS models_without_benchmark
FROM latest_models m
LEFT JOIN latest_benchmark_keys b ON m.benchmark_key = b.model_key
WHERE b.model_key IS NULL
GROUP BY m.model_creator
ORDER BY models_without_benchmark DESC;


-- 8. Integrated Capability and Cost dataset
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT
            b.*,
            ROW_NUMBER() OVER (
                PARTITION BY b.model_key
                ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id
            ) AS rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)
    ) ranked
    WHERE rn = 1
)
SELECT
    f.model_id,
    d.model_name,
    REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
    ROUND(f.prompt_price_per_1m, 4) AS input_price_per_1m,
    ROUND(f.completion_price_per_1m, 4) AS output_price_per_1m,
    f.context_length,
    b.intelligence_index,
    b.coding_index,
    b.agentic_index
FROM fact_model_snapshot f
JOIN dim_model d ON f.model_id = d.model_id
JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
  AND (f.prompt_price_status = 'priced' OR f.completion_price_status = 'priced')
ORDER BY b.intelligence_index DESC NULLS LAST;

SELECT
    CASE
        WHEN model_id LIKE '%:batch' THEN 'batch'
        WHEN model_id LIKE '%:free' THEN 'free'
        ELSE 'standard'
    END AS model_variant,
    COUNT(*) AS model_count
FROM fact_model_snapshot
WHERE snapshot_date = (
    SELECT MAX(snapshot_date)
    FROM fact_model_snapshot
)
GROUP BY 1
ORDER BY 1;