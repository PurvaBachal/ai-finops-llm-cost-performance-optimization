CREATE TABLE IF NOT EXISTS dim_model (
    model_id TEXT PRIMARY KEY,
    model_name TEXT NOT NULL,
    model_creator TEXT,
    canonical_slug TEXT,
    first_seen_date DATE,
    latest_seen_date DATE,
    current_context_length INTEGER,
    current_modality TEXT,
    current_input_modalities TEXT,
    current_output_modalities TEXT,
    current_tokenizer TEXT);


CREATE TABLE IF NOT EXISTS fact_model_snapshot (
    snapshot_date DATE NOT NULL,
    model_id TEXT NOT NULL,
    canonical_slug TEXT,
    prompt_price_per_1m NUMERIC(18, 8),
    prompt_price_status TEXT,
    completion_price_per_1m NUMERIC(18, 8),
    completion_price_status TEXT,
    input_cache_read_price_per_1m NUMERIC(18, 8),
    input_cache_read_price_status TEXT,
    input_cache_write_price_per_1m NUMERIC(18, 8),
    input_cache_write_price_status TEXT,
    request_price NUMERIC(18, 8),
    context_length INTEGER,
    modality TEXT,
    reasoning_default_enabled BOOLEAN,
    is_free_model BOOLEAN,
    is_text_to_text BOOLEAN,
    created_at TIMESTAMPTZ,
    expiration_date DATE,
    knowledge_cutoff DATE,
    max_completion_tokens INTEGER,

    PRIMARY KEY (
        snapshot_date,
        model_id),

    FOREIGN KEY (model_id)
        REFERENCES dim_model (model_id));


CREATE TABLE IF NOT EXISTS fact_benchmark_snapshot (
    snapshot_date DATE NOT NULL,
    benchmark_record_id TEXT NOT NULL,
    source TEXT NOT NULL,
    model_key TEXT NOT NULL,
    benchmark_as_of TIMESTAMPTZ,
    benchmark_version TEXT,
    display_name TEXT,
    intelligence_index NUMERIC(10, 2),
    coding_index NUMERIC(10, 2),
    agentic_index NUMERIC(10, 2),
    benchmark_prompt_price_per_1m NUMERIC(18, 8),
    benchmark_completion_price_per_1m NUMERIC(18, 8),

    PRIMARY KEY (
        snapshot_date,
        benchmark_record_id));


CREATE TABLE IF NOT EXISTS dim_workload (
    workload_profile TEXT PRIMARY KEY,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    capability_metric TEXT NOT NULL,
    use_case TEXT NOT NULL);

SELECT
    'dim_model' AS table_name,
    COUNT(*) AS row_count
FROM dim_model
UNION ALL
SELECT
    'fact_model_snapshot',
    COUNT(*)
FROM fact_model_snapshot
UNION ALL
SELECT
    'fact_benchmark_snapshot',
    COUNT(*)
FROM fact_benchmark_snapshot
UNION ALL
SELECT
    'dim_workload',
    COUNT(*)
FROM dim_workload;

SELECT COUNT(*) AS orphan_model_snapshots
FROM fact_model_snapshot f
LEFT JOIN dim_model d
    ON f.model_id = d.model_id
WHERE d.model_id IS NULL;