-- 1. Workload Profiles Baseline
-- Inspect active workload profiles, token assumptions, and capability targets.
SELECT
    workload_profile,
    input_tokens,
    output_tokens,
    capability_metric,
    use_case
FROM dim_workload
ORDER BY workload_profile;

-- 2. Model Cost & Capability Mapping
-- Joins latest pricing snapshots with benchmark scores per workload profile. Keep models with usable pricing and benchmark coverage.
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
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)) x
    WHERE rn = 1),
current_models AS (
    SELECT
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        f.prompt_price_per_1m,
        f.completion_price_per_1m,
        f.prompt_price_status,
        f.completion_price_status,
        COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) AS benchmark_key
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)),
model_workloads AS (
    SELECT
        m.model_id,
        m.model_name,
        m.model_creator,
        w.workload_profile,
        w.use_case,
        w.input_tokens,
        w.output_tokens,
        w.capability_metric,
        m.prompt_price_per_1m AS input_price_per_1m,
        m.completion_price_per_1m AS output_price_per_1m,
        ROUND((w.input_tokens * m.prompt_price_per_1m / 1000000.0) + (w.output_tokens * m.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
        CASE
          WHEN w.capability_metric = 'intelligence_index' THEN b.intelligence_index
          WHEN w.capability_metric = 'coding_index'       THEN b.coding_index
          WHEN w.capability_metric = 'agentic_index'      THEN b.agentic_index
    END AS relevant_capability_score
    FROM current_models m
    JOIN latest_benchmarks b ON m.benchmark_key = b.model_key
    CROSS JOIN dim_workload w
    WHERE m.prompt_price_status IN ('priced', 'free')
      AND m.completion_price_status IN ('priced', 'free')
)
SELECT
    model_id,
    model_name,
    model_creator,
    workload_profile,
    use_case,
    capability_metric,
    ROUND(input_price_per_1m, 4) AS input_price_per_1m,
    ROUND(output_price_per_1m, 4) AS output_price_per_1m,
    estimated_workload_cost,
    ROUND(relevant_capability_score, 2) AS relevant_capability_score
FROM model_workloads
WHERE relevant_capability_score IS NOT NULL
ORDER BY workload_profile, estimated_workload_cost;


-- 3. Cost & Capability Ranking vs. Profile Best
-- Compares model cost and capability against the top-performing model per workload, calculating relative savings and top 10 budget ranks.
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
    ) x
    WHERE rn = 1
),
model_workloads AS (
    SELECT
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        w.workload_profile,
        w.capability_metric,
        ROUND((w.input_tokens * f.prompt_price_per_1m / 1000000.0) + (w.output_tokens * f.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
        CASE
            WHEN w.capability_metric IN ('intelligence', 'intelligence_index') THEN b.intelligence_index
            WHEN w.capability_metric IN ('coding', 'coding_index')             THEN b.coding_index
            WHEN w.capability_metric IN ('agentic', 'agentic_index')           THEN b.agentic_index
        END AS relevant_capability_score
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
    CROSS JOIN dim_workload w
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
      AND f.prompt_price_status IN ('priced', 'free')
      AND f.completion_price_status IN ('priced', 'free')
),
workload_scores AS (
    SELECT
        *,
        MAX(relevant_capability_score) OVER (PARTITION BY workload_profile) AS best_capability_score
    FROM model_workloads
    WHERE relevant_capability_score IS NOT NULL
),
ranked_models AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY workload_profile
            ORDER BY relevant_capability_score DESC, estimated_workload_cost ASC
        ) AS capability_rank
    FROM workload_scores
),
baseline_costs AS (
    SELECT
        workload_profile,
        estimated_workload_cost AS baseline_cost
    FROM ranked_models
    WHERE capability_rank = 1
),
cost_ranked AS (
    SELECT
        r.*,
        ROUND(r.best_capability_score - r.relevant_capability_score, 2) AS capability_difference,
        ROUND(100.0 * (b.baseline_cost - r.estimated_workload_cost) / NULLIF(b.baseline_cost, 0), 2) AS relative_savings_pct,
        ROW_NUMBER() OVER (
            PARTITION BY r.workload_profile
            ORDER BY r.estimated_workload_cost ASC, r.relevant_capability_score DESC
        ) AS cost_rank
    FROM ranked_models r
    JOIN baseline_costs b ON r.workload_profile = b.workload_profile
)
SELECT
    workload_profile,
    model_id,
    model_name,
    model_creator,
    capability_metric,
    ROUND(estimated_workload_cost, 8) AS estimated_workload_cost,
    ROUND(relevant_capability_score, 2) AS relevant_capability_score,
    capability_difference,
    relative_savings_pct,
    cost_rank
FROM cost_ranked
WHERE cost_rank <= 10
ORDER BY workload_profile, cost_rank;

-- 3A. Paid Cost & Capability Comparison by Workload
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT b.*,
               ROW_NUMBER() OVER(PARTITION BY b.model_key ORDER BY b.benchmark_as_of DESC NULLS LAST, b.benchmark_record_id) as rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_benchmark_snapshot)) x
    WHERE rn = 1),

model_workloads AS (
    SELECT 
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        w.workload_profile,
        w.capability_metric,
        ROUND((w.input_tokens * f.prompt_price_per_1m / 1000000.0) + (w.output_tokens * f.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
        CASE 
            WHEN w.capability_metric = 'intelligence_index' THEN b.intelligence_index
            WHEN w.capability_metric = 'coding_index' THEN b.coding_index
            WHEN w.capability_metric = 'agentic_index' THEN b.agentic_index
        END AS relevant_capability_score
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
    CROSS JOIN dim_workload w
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
      AND f.prompt_price_status IN ('priced', 'free')
      AND f.completion_price_status IN ('priced', 'free')),
paid_model_workloads AS (
    SELECT * 
    FROM model_workloads 
    WHERE estimated_workload_cost > 0 
      AND relevant_capability_score IS NOT NULL),
workload_reference AS (
    SELECT 
        *,
        MAX(relevant_capability_score) OVER(PARTITION BY workload_profile) AS max_capability_score,
        MAX(estimated_workload_cost) OVER(PARTITION BY workload_profile) AS max_workload_cost
    FROM paid_model_workloads),
ranked_options AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY workload_profile ORDER BY estimated_workload_cost ASC, relevant_capability_score DESC, model_id) AS cost_rank
    FROM workload_reference)
 SELECT 
    workload_profile,
    model_id,
    model_name,
    model_creator,
    capability_metric,
    ROUND(estimated_workload_cost, 8) AS estimated_workload_cost,
    ROUND(relevant_capability_score, 2) AS relevant_capability_score,
    ROUND(max_capability_score - relevant_capability_score, 2) AS capability_difference,
    ROUND(100.0 * (max_workload_cost - estimated_workload_cost) / NULLIF(max_workload_cost, 0), 2) AS relative_savings_pct,
    cost_rank
FROM ranked_options
WHERE cost_rank <= 10
ORDER BY 
    workload_profile, 
    cost_rank;

-- 4. Best Capability Upgrades per Price Tier
-- Identifies models where higher cost is associated with higher capability than all cheaper options.
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
    ) x
    WHERE rn = 1
),
model_workloads AS (
    SELECT
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        w.workload_profile,
        w.capability_metric,
        ROUND((w.input_tokens * f.prompt_price_per_1m / 1000000.0) + (w.output_tokens * f.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
        CASE
         WHEN w.capability_metric = 'intelligence_index' THEN b.intelligence_index
         WHEN w.capability_metric = 'coding_index'       THEN b.coding_index
         WHEN w.capability_metric = 'agentic_index'      THEN b.agentic_index
    END AS relevant_capability_score
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
    CROSS JOIN dim_workload w
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
      AND f.prompt_price_status IN ('priced', 'free')
      AND f.completion_price_status IN ('priced', 'free')
),
valid_models AS (
    SELECT *
    FROM model_workloads
    WHERE relevant_capability_score IS NOT NULL
),
cost_levels AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY workload_profile, estimated_workload_cost
            ORDER BY relevant_capability_score DESC, model_id
        ) AS cost_rank
    FROM valid_models
),
frontier_check AS (
    SELECT
        *,
        MAX(relevant_capability_score) OVER (
            PARTITION BY workload_profile
            ORDER BY estimated_workload_cost ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS best_capability_at_lower_cost
    FROM cost_levels
    WHERE cost_rank = 1
)
SELECT
    workload_profile,
    model_id,
    model_name,
    model_creator,
    capability_metric,
    ROUND(estimated_workload_cost, 8) AS estimated_workload_cost,
    ROUND(relevant_capability_score, 2) AS relevant_capability_score
FROM frontier_check
WHERE best_capability_at_lower_cost IS NULL
   OR relevant_capability_score > best_capability_at_lower_cost
ORDER BY workload_profile, estimated_workload_cost;


-- 5. Price-to-Performance Range Summary
-- Summarizes the cost and capability range of frontier models.
WITH frontier_models AS (
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
        ) x
        WHERE rn = 1
    ),
    model_workloads AS (
        SELECT
            f.model_id,
            w.workload_profile,
            w.capability_metric,
            ROUND((w.input_tokens * f.prompt_price_per_1m / 1000000.0) + (w.output_tokens * f.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
            CASE
             WHEN w.capability_metric = 'intelligence_index' THEN b.intelligence_index
             WHEN w.capability_metric = 'coding_index'       THEN b.coding_index
             WHEN w.capability_metric = 'agentic_index'      THEN b.agentic_index
        END AS relevant_capability_score
        FROM fact_model_snapshot f
        JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
        CROSS JOIN dim_workload w
        WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
          AND f.prompt_price_status IN ('priced', 'free')
          AND f.completion_price_status IN ('priced', 'free')
    ),
    valid_models AS (
        SELECT *
        FROM model_workloads
        WHERE relevant_capability_score IS NOT NULL
    ),
    cost_levels AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY workload_profile, estimated_workload_cost
                ORDER BY relevant_capability_score DESC
            ) AS cost_rank
        FROM valid_models
    ),
    frontier_check AS (
        SELECT
            *,
            MAX(relevant_capability_score) OVER (
                PARTITION BY workload_profile
                ORDER BY estimated_workload_cost ASC
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS best_capability_at_lower_cost
        FROM cost_levels
        WHERE cost_rank = 1
    )
    SELECT *
    FROM frontier_check
    WHERE best_capability_at_lower_cost IS NULL
       OR relevant_capability_score > best_capability_at_lower_cost
)
SELECT
    workload_profile,
    capability_metric,
    COUNT(*) AS frontier_model_options,
    ROUND(MIN(estimated_workload_cost), 8) AS lowest_frontier_cost,
    ROUND(MAX(estimated_workload_cost), 8) AS highest_frontier_cost,
    ROUND(MIN(relevant_capability_score), 2) AS lowest_frontier_capability,
    ROUND(MAX(relevant_capability_score), 2) AS highest_frontier_capability
FROM frontier_models
GROUP BY workload_profile, capability_metric
ORDER BY workload_profile;


-- 6. Top 5 Lowest-Cost Alternatives by Workload
-- Quick lookup for budget-constrained production implementations ranking top 5 options.
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
    ) x
    WHERE rn = 1
),
model_workloads AS (
    SELECT
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(COALESCE(d.model_creator, 'Unknown'), '^~', '') AS model_creator,
        w.workload_profile,
        w.capability_metric,
        ROUND((w.input_tokens * f.prompt_price_per_1m / 1000000.0) + (w.output_tokens * f.completion_price_per_1m / 1000000.0), 8) AS estimated_workload_cost,
        CASE
         WHEN w.capability_metric = 'intelligence_index' THEN b.intelligence_index
         WHEN w.capability_metric = 'coding_index'       THEN b.coding_index
         WHEN w.capability_metric = 'agentic_index'      THEN b.agentic_index
    END AS relevant_capability_score
    FROM fact_model_snapshot f
    JOIN dim_model d ON f.model_id = d.model_id
    JOIN latest_benchmarks b ON COALESCE(NULLIF(f.canonical_slug, ''), f.model_id) = b.model_key
    CROSS JOIN dim_workload w
    WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_model_snapshot)
      AND f.prompt_price_status IN ('priced', 'free')
      AND f.completion_price_status IN ('priced', 'free')
),
ranked_options AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY workload_profile
            ORDER BY estimated_workload_cost ASC, relevant_capability_score DESC
        ) AS cost_rank
    FROM model_workloads
    WHERE relevant_capability_score IS NOT NULL
)
SELECT
    workload_profile,
    model_id,
    model_name,
    model_creator,
    capability_metric,
    ROUND(estimated_workload_cost, 8) AS estimated_workload_cost,
    ROUND(relevant_capability_score, 2) AS relevant_capability_score,
    cost_rank
FROM ranked_options
WHERE cost_rank <= 5
ORDER BY workload_profile, cost_rank;

-- 7. Paid Cost Alternatives by Workload
-- Top 5 lowest-cost paid models for each workload profile.
WITH latest_benchmarks AS (
    SELECT *
    FROM (
        SELECT
            b.*,
            ROW_NUMBER() OVER (
                PARTITION BY b.model_key
                ORDER BY b.benchmark_as_of DESC NULLS LAST,
                         b.benchmark_record_id
            ) AS rn
        FROM fact_benchmark_snapshot b
        WHERE b.snapshot_date = (
            SELECT MAX(snapshot_date)
            FROM fact_benchmark_snapshot
        )
    ) x
    WHERE rn = 1
),
model_workloads AS (
    SELECT
        f.model_id,
        d.model_name,
        REGEXP_REPLACE(
            COALESCE(d.model_creator, 'Unknown'),
            '^~',
            ''
        ) AS model_creator,
        w.workload_profile,
        w.capability_metric,
        ROUND(
            (
                w.input_tokens * f.prompt_price_per_1m / 1000000.0
            ) +
            (
                w.output_tokens * f.completion_price_per_1m / 1000000.0
            ),
            8
        ) AS estimated_workload_cost,
        CASE
            WHEN w.capability_metric = 'intelligence_index'
                THEN b.intelligence_index
            WHEN w.capability_metric = 'coding_index'
                THEN b.coding_index
            WHEN w.capability_metric = 'agentic_index'
                THEN b.agentic_index
        END AS relevant_capability_score
    FROM fact_model_snapshot f
    JOIN dim_model d
        ON f.model_id = d.model_id
    JOIN latest_benchmarks b
        ON COALESCE(
            NULLIF(f.canonical_slug, ''),
            f.model_id
        ) = b.model_key
    CROSS JOIN dim_workload w
    WHERE f.snapshot_date = (
        SELECT MAX(snapshot_date)
        FROM fact_model_snapshot
    )
      AND f.prompt_price_status IN ('priced', 'free')
      AND f.completion_price_status IN ('priced', 'free')
),
paid_models AS (
    SELECT *
    FROM model_workloads
    WHERE estimated_workload_cost > 0
      AND relevant_capability_score IS NOT NULL
),
ranked_options AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY workload_profile
            ORDER BY
                estimated_workload_cost ASC,
                relevant_capability_score DESC
        ) AS cost_rank
    FROM paid_models
)
SELECT
    workload_profile,
    model_id,
    model_name,
    model_creator,
    capability_metric,
    ROUND(estimated_workload_cost, 8)
        AS estimated_workload_cost,
    ROUND(relevant_capability_score, 2)
        AS relevant_capability_score,
    cost_rank
FROM ranked_options
WHERE cost_rank <= 5
ORDER BY
    workload_profile,
    cost_rank;