-- 1. Latest market snapshot
WITH latest_snapshot AS (
SELECT MAX(snapshot_date) AS snapshot_date
FROM fact_model_snapshot)
SELECT f.snapshot_date,
COUNT(*) AS total_models,
COUNT(*) FILTER (
WHERE f.is_free_model = TRUE) AS free_models,
COUNT(*) FILTER (
WHERE f.prompt_price_status = 'priced'
) AS priced_models,
COUNT(
DISTINCT REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~',
'')) AS model_creators,
ROUND(AVG(f.context_length)::numeric, 0) AS avg_context_length
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
JOIN latest_snapshot l
ON f.snapshot_date = l.snapshot_date
GROUP BY f.snapshot_date;

-- 2. Model distribution by creator
SELECT
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~',
'') AS model_creator,
COUNT(*) AS model_count,
ROUND(
100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
2) AS model_share_pct
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
GROUP BY
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~','')
ORDER BY model_count DESC;

-- 3. Free vs priced model mix
SELECT
CASE
WHEN f.is_free_model = TRUE THEN 'Free'
WHEN f.prompt_price_status = 'priced'
OR f.completion_price_status = 'priced' THEN 'Priced'
WHEN f.prompt_price_status = 'negative_sentinel'
OR f.completion_price_status = 'negative_sentinel' THEN 'Pricing Exception'
ELSE 'Missing Pricing'
END AS pricing_category,
COUNT(*) AS model_count,
ROUND(
100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS model_share_pct
FROM fact_model_snapshot f
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
GROUP BY 1
ORDER BY model_count DESC;

-- 4. Input pricing distribution by creator
WITH latest_models AS (
SELECT
f.model_id,
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~', '') AS model_creator,
f.prompt_price_per_1m,
f.prompt_price_status
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot))
SELECT
model_creator,
COUNT(*) AS priced_models,
ROUND(
MIN(prompt_price_per_1m)::numeric, 2) AS min_input_price_per_1m,
ROUND(
PERCENTILE_CONT(0.25)
WITHIN GROUP (
ORDER BY prompt_price_per_1m
)::numeric, 2) AS p25_input_price_per_1m,
ROUND(
PERCENTILE_CONT(0.50)
WITHIN GROUP (
ORDER BY prompt_price_per_1m
)::numeric, 2) AS median_input_price_per_1m,
ROUND(
PERCENTILE_CONT(0.75)
WITHIN GROUP (
ORDER BY prompt_price_per_1m
)::numeric, 2) AS p75_input_price_per_1m,
ROUND(
MAX(prompt_price_per_1m)::numeric, 2) AS max_input_price_per_1m
FROM latest_models
WHERE prompt_price_status = 'priced'
GROUP BY model_creator
ORDER BY median_input_price_per_1m DESC;

-- 5. Output pricing distribution by creator
WITH latest_models AS (
SELECT
f.model_id,
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~','') AS model_creator,
f.completion_price_per_1m,
f.completion_price_status
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot))
SELECT
model_creator,
COUNT(*) AS priced_models,
ROUND(
MIN(completion_price_per_1m)::numeric, 2) AS min_output_price_per_1m,
ROUND(
PERCENTILE_CONT(0.25)
WITHIN GROUP (
ORDER BY completion_price_per_1m
)::numeric, 2) AS p25_output_price_per_1m,
ROUND(
PERCENTILE_CONT(0.50)
WITHIN GROUP (
ORDER BY completion_price_per_1m
)::numeric, 2) AS median_output_price_per_1m,
ROUND(
PERCENTILE_CONT(0.75)
WITHIN GROUP (
ORDER BY completion_price_per_1m
)::numeric, 2) AS p75_output_price_per_1m,
ROUND(
MAX(completion_price_per_1m)::numeric, 2) AS max_output_price_per_1m
FROM latest_models
WHERE completion_price_status = 'priced'
GROUP BY model_creator
ORDER BY median_output_price_per_1m DESC;

-- 6. Cheapest and most expensive models by input price
WITH latest_models AS (
SELECT
f.model_id,
d.model_name,
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~', '') AS model_creator,
f.prompt_price_per_1m
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
AND f.prompt_price_status = 'priced'),
ranked_models AS (
SELECT *,
DENSE_RANK() OVER (
ORDER BY prompt_price_per_1m ASC) AS cheapest_rank,
DENSE_RANK() OVER (
ORDER BY prompt_price_per_1m DESC) AS highest_rank
FROM latest_models)
SELECT
model_id,
model_name,
model_creator,
ROUND(
prompt_price_per_1m::numeric, 4) AS prompt_price_per_1m,
cheapest_rank,
highest_rank
FROM ranked_models
WHERE cheapest_rank <= 10
OR highest_rank <= 10
ORDER BY prompt_price_per_1m, model_name;

-- 7. Model context-length distribution
SELECT
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~', '') AS model_creator,
COUNT(*) AS model_count,
ROUND(
AVG(f.context_length)::numeric, 0) AS avg_context_length,
MIN(f.context_length) AS min_context_length,
MAX(f.context_length) AS max_context_length
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
AND f.context_length IS NOT NULL
GROUP BY
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~', '')
ORDER BY avg_context_length DESC;

-- 8. Model modality mix
SELECT
COALESCE(f.modality, 'Unknown') AS modality,
COUNT(*) AS model_count,
ROUND(
100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),2) AS model_share_pct
FROM fact_model_snapshot f
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
GROUP BY f.modality
ORDER BY model_count DESC;

-- 9. Pricing exceptions requiring review
SELECT
f.model_id,
f.prompt_price_status,
f.completion_price_status,
f.prompt_price_per_1m,
f.completion_price_per_1m
FROM fact_model_snapshot f
WHERE f.snapshot_date = (
SELECT MAX(snapshot_date)
FROM fact_model_snapshot)
AND (
f.prompt_price_status IN ('negative_sentinel', 'missing')
OR f.completion_price_status IN ('negative_sentinel', 'missing'))
ORDER BY f.model_id;

-- 10. Price changes over time
WITH price_history AS (
SELECT
f.snapshot_date,
f.model_id,
d.model_name,
REGEXP_REPLACE(
COALESCE(d.model_creator, 'Unknown'),
'^~', '') AS model_creator,
f.prompt_price_per_1m,
LAG(f.prompt_price_per_1m) OVER (
PARTITION BY f.model_id
ORDER BY f.snapshot_date) AS previous_prompt_price
FROM fact_model_snapshot f
JOIN dim_model d
ON f.model_id = d.model_id
WHERE f.prompt_price_status = 'priced')
SELECT
snapshot_date,
model_id,
model_name,
model_creator,
ROUND(
previous_prompt_price::numeric, 4) AS previous_prompt_price_per_1m,
ROUND(
prompt_price_per_1m::numeric, 4) AS current_prompt_price_per_1m,
ROUND((
(prompt_price_per_1m - previous_prompt_price)
/ NULLIF(previous_prompt_price, 0) * 100
)::numeric, 2) AS price_change_pct
FROM price_history
WHERE previous_prompt_price IS NOT NULL
AND prompt_price_per_1m IS NOT NULL
AND prompt_price_per_1m <> previous_prompt_price
ORDER BY ABS(
(prompt_price_per_1m - previous_prompt_price)
/ NULLIF(previous_prompt_price, 0)) DESC;