from pathlib import Path
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"

REQUIRED_FILES = {
    "model_snapshot": "model_snapshot.csv",
    "benchmark_snapshot": "benchmark_snapshot.csv",
    "workload_assumptions": "workload_assumptions.csv",
}

def load_datasets():
    """Pulls the processed CSVs into Pandas DataFrames for quality checks."""
    datasets = {}
    for name, filename in REQUIRED_FILES.items():
        file_path = PROCESSED_DATA_DIR / filename
        if not file_path.exists():
            raise FileNotFoundError(f"Missing processed file: {file_path}")
        datasets[name] = pd.read_csv(file_path)
    return datasets

def validate_model_snapshot(df: pd.DataFrame) -> dict:
    # On the exact same snapshot date a model shouldn't appear twice
    duplicate_keys = df.duplicated(subset=["snapshot_date", "model_id"]).sum()
    
    context_lengths = pd.to_numeric(df["context_length"], errors="coerce")
    invalid_context = (context_lengths.notna() & (context_lengths <= 0)).sum()

    return {
        "rows": len(df),
        "duplicate_model_keys": int(duplicate_keys),
        "invalid_context_length": int(invalid_context),
        "negative_prompt_sentinels": int((df["prompt_price_status"] == "negative_sentinel").sum()),
        "negative_completion_sentinels": int((df["completion_price_status"] == "negative_sentinel").sum()),
        "missing_prompt_prices": int((df["prompt_price_status"] == "missing").sum()),
        "missing_completion_prices": int((df["completion_price_status"] == "missing").sum()),
    }

def validate_benchmark_snapshot(df: pd.DataFrame) -> dict:
    duplicate_keys = df.duplicated(subset=["snapshot_date", "benchmark_record_id"]).sum()
    
    # Checked for negative indices (intelligence/coding/agentic shouldn't be negative)
    negative_values = 0
    for column in ["intelligence_index", "coding_index", "agentic_index"]:
        numeric_values = pd.to_numeric(df[column], errors="coerce")
        negative_values += int((numeric_values.notna() & (numeric_values < 0)).sum())

    return {
        "rows": len(df),
        "duplicate_benchmark_keys": int(duplicate_keys),
        "exact_duplicate_rows": int(df.duplicated().sum()),
        "missing_model_keys": int(df["model_key"].isna().sum()),
        "negative_benchmark_values": int(negative_values),
    }

def validate_workloads(df: pd.DataFrame) -> dict:
    input_tokens = pd.to_numeric(df["input_tokens"], errors="coerce")
    output_tokens = pd.to_numeric(df["output_tokens"], errors="coerce")

    return {
        "rows": len(df),
        "duplicate_workloads": int(df["workload_profile"].duplicated().sum()),
        "invalid_input_tokens": int((input_tokens.isna() | (input_tokens <= 0)).sum()),
        "invalid_output_tokens": int((output_tokens.isna() | (output_tokens <= 0)).sum()),
        "missing_capability_metric": int(df["capability_metric"].isna().sum()),
    }

def calculate_benchmark_coverage(model_df: pd.DataFrame, benchmark_df: pd.DataFrame) -> dict:
    """Checks how many benchmarked models actually map to our model dimension."""
    model_keys = set(model_df["benchmark_key"].dropna().astype(str))
    benchmark_keys = set(benchmark_df["model_key"].dropna().astype(str))
    
    matched_keys = model_keys.intersection(benchmark_keys)
    match_rate = len(matched_keys) / len(benchmark_keys) if benchmark_keys else None

    return {
        "model_benchmark_keys": len(model_keys),
        "benchmark_keys": len(benchmark_keys),
        "matched_keys": len(matched_keys),
        "unmatched_benchmark_keys": len(benchmark_keys - model_keys),
        "benchmark_key_match_rate": match_rate,
    }

def calculate_model_movement(df: pd.DataFrame) -> dict:
    """Tracks how many models were added or deprecated between the two most recent snapshots."""
    dates = sorted(df["snapshot_date"].dropna().astype(str).unique())
    
    if len(dates) < 2:
        return {"new_models": None, "removed_models": None, "comparison_status": "Need >= 2 snapshots for movement calc."}

    previous_models = set(df.loc[df["snapshot_date"].astype(str) == dates[-2], "model_id"].dropna())
    latest_models = set(df.loc[df["snapshot_date"].astype(str) == dates[-1], "model_id"].dropna())

    return {
        "new_models": len(latest_models - previous_models),
        "removed_models": len(previous_models - latest_models),
        "comparison_status": "Compared",
    }

def main():
    datasets = load_datasets()

    # Compile the DQ report 
    report = [
        {"dataset": "model_snapshot", **validate_model_snapshot(datasets["model_snapshot"])},
        {"dataset": "benchmark_snapshot", **validate_benchmark_snapshot(datasets["benchmark_snapshot"])},
        {"dataset": "workload_assumptions", **validate_workloads(datasets["workload_assumptions"])},
        {"dataset": "benchmark_coverage", **calculate_benchmark_coverage(datasets["model_snapshot"], datasets["benchmark_snapshot"])},
        {"dataset": "model_movement", **calculate_model_movement(datasets["model_snapshot"])},
    ]

    report_df = pd.DataFrame(report)
    report_path = PROCESSED_DATA_DIR / "data_quality_report.csv"
    report_df.to_csv(report_path, index=False)

    print("Data quality validation completed. Results:")
    for result in report:
        print(result)

if __name__ == "__main__":
    main()