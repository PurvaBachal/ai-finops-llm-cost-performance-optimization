import hashlib
import json
from pathlib import Path
import pandas as pd

# Set up paths relative to this script
PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw" / "openrouter"
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"

# Baseline assumptions for the arbitrage calculations
WORKLOAD_ASSUMPTIONS = [
    {"workload_profile": "Summarization", "input_tokens": 4000, "output_tokens": 800, "capability_metric": "intelligence_index", "use_case": "Summarizing documents, reports and long-form content."},
    {"workload_profile": "Classification", "input_tokens": 1000, "output_tokens": 100, "capability_metric": "intelligence_index", "use_case": "Classification, routing and tagging tasks."},
    {"workload_profile": "Customer Support", "input_tokens": 2500, "output_tokens": 500, "capability_metric": "intelligence_index", "use_case": "Customer-facing responses and support assistance."},
    {"workload_profile": "Code Assistance", "input_tokens": 6000, "output_tokens": 1200, "capability_metric": "coding_index", "use_case": "Code generation, explanation and debugging."},
    {"workload_profile": "Reasoning", "input_tokens": 8000, "output_tokens": 2000, "capability_metric": "intelligence_index", "use_case": "Complex reasoning and multi-step analytical tasks."},
    {"workload_profile": "Extraction", "input_tokens": 2500, "output_tokens": 500, "capability_metric": "intelligence_index", "use_case": "Structured information extraction from documents."},
]

def read_json(file_path: Path):
    with file_path.open("r", encoding="utf-8") as file:
        return json.load(file)

def to_float(value):
    if value in (None, "", "null"):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def classify_price(value):
    """Parses raw pricing and converts it to a standard per-1M token rate."""
    numeric_value = to_float(value)

    if numeric_value is None:
        return None, "missing"
    
    # Some APIs use -1 to indicate a metric isn't applicable
    if numeric_value < 0:
        return None, "negative_sentinel"
    if numeric_value == 0:
        return 0.0, "free"

    # Multiply by 1M to standardize the cost metric for analysis
    return numeric_value * 1_000_000, "priced"

def create_benchmark_record_id(*args) -> str:
    """Generates a stable hash ID for a benchmark observation so we can track changes over time."""
    raw_value = "|".join("" if value is None else str(value) for value in args)
    return hashlib.sha256(raw_value.encode("utf-8")).hexdigest()[:16]

def get_snapshot_directories():
    # Found all snapshot folders that actually have both required JSON files
    return sorted(
        path for path in RAW_DATA_DIR.iterdir()
        if path.is_dir() and (path / "models.json").exists() and (path / "benchmarks.json").exists()
    )

def build_model_snapshot(snapshot_dir: Path) -> pd.DataFrame:
    payload = read_json(snapshot_dir / "models.json")
    rows = []

    for model in payload.get("data", []):
        architecture = model.get("architecture") or {}
        pricing = model.get("pricing") or {}
        top_provider = model.get("top_provider") or {}
        reasoning = model.get("reasoning") or {}

        model_id = model.get("id")
        canonical_slug = model.get("canonical_slug")
        
        # Extracted the creator from the model ID (e.g., 'openai/gpt-4' -> 'openai')
        model_creator = model_id.split("/", 1)[0] if isinstance(model_id, str) and "/" in model_id else None

        input_modalities = architecture.get("input_modalities", [])
        output_modalities = architecture.get("output_modalities", [])

        prompt_price, prompt_status = classify_price(pricing.get("prompt"))
        completion_price, completion_status = classify_price(pricing.get("completion"))
        cache_read_price, cache_read_status = classify_price(pricing.get("input_cache_read"))
        cache_write_price, cache_write_status = classify_price(pricing.get("input_cache_write"))

        rows.append({
            "snapshot_date": snapshot_dir.name,
            "model_key": model_id,
            "benchmark_key": canonical_slug or model_id,
            "model_id": model_id,
            "canonical_slug": canonical_slug,
            "model_name": model.get("name"),
            "model_creator": model_creator,
            "context_length": model.get("context_length"),
            "modality": architecture.get("modality"),
            "input_modalities": "|".join(input_modalities) if input_modalities else None,
            "output_modalities": "|".join(output_modalities) if output_modalities else None,
            "tokenizer": architecture.get("tokenizer"),
            "prompt_price_per_1m": prompt_price,
            "prompt_price_status": prompt_status,
            "completion_price_per_1m": completion_price,
            "completion_price_status": completion_status,
            "input_cache_read_price_per_1m": cache_read_price,
            "input_cache_read_price_status": cache_read_status,
            "input_cache_write_price_per_1m": cache_write_price,
            "input_cache_write_price_status": cache_write_status,
            "request_price": to_float(pricing.get("request")),
            "created_at": pd.to_datetime(model.get("created"), unit="s", utc=True, errors="coerce"),
            "expiration_date": model.get("expiration_date"),
            "knowledge_cutoff": model.get("knowledge_cutoff"),
            "max_completion_tokens": top_provider.get("max_completion_tokens"),
            "reasoning_default_enabled": reasoning.get("default_enabled"),
            "is_free_model": (prompt_status == "free" and completion_status == "free"),
            "is_text_to_text": ("text" in input_modalities and "text" in output_modalities),
        })

    return pd.DataFrame(rows)

def build_benchmark_snapshot(snapshot_dir: Path) -> pd.DataFrame:
    payload = read_json(snapshot_dir / "benchmarks.json")
    metadata = payload.get("meta") or {}
    rows = []

    for benchmark in payload.get("data", []):
        pricing = benchmark.get("pricing") or {}
        prompt_price, _ = classify_price(pricing.get("prompt"))
        completion_price, _ = classify_price(pricing.get("completion"))
        benchmark_as_of = metadata.get("as_of")

        record_id = create_benchmark_record_id(
            benchmark.get("source"),
            benchmark.get("model_permaslug"),
            benchmark_as_of,
            benchmark.get("display_name"),
            benchmark.get("intelligence_index"),
            benchmark.get("coding_index"),
            benchmark.get("agentic_index"),
            pricing.get("prompt"),
            pricing.get("completion"),
        )

        rows.append({
            "snapshot_date": snapshot_dir.name,
            "benchmark_record_id": record_id,
            "benchmark_as_of": benchmark_as_of,
            "benchmark_version": metadata.get("version"),
            "source": benchmark.get("source"),
            "model_key": benchmark.get("model_permaslug"),
            "display_name": benchmark.get("display_name"),
            "intelligence_index": to_float(benchmark.get("intelligence_index")),
            "coding_index": to_float(benchmark.get("coding_index")),
            "agentic_index": to_float(benchmark.get("agentic_index")),
            "benchmark_prompt_price_per_1m": prompt_price,
            "benchmark_completion_price_per_1m": completion_price,
        })

    return pd.DataFrame(rows)

def main():
    PROCESSED_DATA_DIR.mkdir(parents=True, exist_ok=True)
    snapshot_dirs = get_snapshot_directories()

    if not snapshot_dirs:
        raise FileNotFoundError("No complete OpenRouter snapshots were found in the raw data directory.")

    model_frames = []
    benchmark_frames = []

    # Process each snapshot date folder
    for snapshot_dir in snapshot_dirs:
        model_frames.append(build_model_snapshot(snapshot_dir))
        benchmark_frames.append(build_benchmark_snapshot(snapshot_dir))

    # Combine all snapshots into main dataframes and drop exact duplicates
    model_snapshot = pd.concat(model_frames, ignore_index=True).drop_duplicates()
    benchmark_snapshot = pd.concat(benchmark_frames, ignore_index=True).drop_duplicates()
    workload_assumptions = pd.DataFrame(WORKLOAD_ASSUMPTIONS)

    # Save to processed layer
    model_snapshot.to_csv(PROCESSED_DATA_DIR / "model_snapshot.csv", index=False)
    benchmark_snapshot.to_csv(PROCESSED_DATA_DIR / "benchmark_snapshot.csv", index=False)
    workload_assumptions.to_csv(PROCESSED_DATA_DIR / "workload_assumptions.csv", index=False)

    print("--- Data Transformation Complete ---")
    print(f"Total Model rows generated: {len(model_snapshot):,}")
    print(f"Total Benchmark rows generated: {len(benchmark_snapshot):,}")
    print(f"Total Workload rows generated: {len(workload_assumptions):,}")

if __name__ == "__main__":
    main()