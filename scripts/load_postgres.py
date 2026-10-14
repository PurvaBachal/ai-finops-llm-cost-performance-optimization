import logging
import os
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",)

logger = logging.getLogger(__name__)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"
STAGING_DATA_DIR = PROJECT_ROOT / "data" / "staging"

def get_database_url() -> str:
    """Load the PostgreSQL connection string."""
    load_dotenv(PROJECT_ROOT / ".env")

    database_url = os.getenv("DATABASE_URL", "").strip()

    if not database_url:
        raise ValueError(
            "DATABASE_URL is missing from the .env file.")

    return database_url


def load_processed_data() -> tuple[
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame]:
    """Load the processed datasets."""
    logger.info("Loading processed datasets.")

    model_df = pd.read_csv(PROCESSED_DATA_DIR / "model_snapshot.csv")

    benchmark_df = pd.read_csv(PROCESSED_DATA_DIR / "benchmark_snapshot.csv")

    workload_df = pd.read_csv(STAGING_DATA_DIR / "workload_assumptions.csv")

    return model_df, benchmark_df, workload_df


def validate_input_data(
    model_df: pd.DataFrame,
    benchmark_df: pd.DataFrame,
    workload_df: pd.DataFrame,
) -> None:
    """Validate database keys before loading."""
    model_duplicates = model_df.duplicated(
        subset=[
            "snapshot_date",
            "model_id",]).sum()

    benchmark_duplicates = benchmark_df.duplicated(
        subset=[
            "snapshot_date",
            "benchmark_record_id",]).sum()

    workload_duplicates = workload_df.duplicated(
        subset=["workload_profile",]).sum()

    if model_duplicates:
        raise ValueError(
            "Duplicate model snapshot keys found: "
            f"{model_duplicates}")

    if benchmark_duplicates:
        raise ValueError(
            "Duplicate benchmark record keys found: "
            f"{benchmark_duplicates}")

    if workload_duplicates:
        raise ValueError(
            "Duplicate workload keys found: "
            f"{workload_duplicates}")


def clean_dataframe_for_postgres(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Convert Pandas missing values to Python None."""
    return df.astype(object).where(
        pd.notna(df),
        None,)


def to_python_bool(value):
    """Convert a Pandas value to a nullable Python boolean."""
    if pd.isna(value):
        return None

    if isinstance(value, bool):
        return value

    return str(value).strip().lower() == "true"


def prepare_model_dimension(
    model_df: pd.DataFrame,
) -> list[tuple]:
    """Prepare the current model dimension."""
    df = model_df.copy()

    df["snapshot_date"] = pd.to_datetime(
        df["snapshot_date"],
        errors="coerce",)

    date_ranges = (
        df.groupby("model_id")["snapshot_date"]
        .agg(
            first_seen_date="min",
            latest_seen_date="max",)
        .reset_index())

    latest_rows = (
        df.sort_values("snapshot_date")
        .drop_duplicates(
            subset=["model_id"],
            keep="last",))

    dim_df = latest_rows.merge(
        date_ranges,
        on="model_id",
        how="left",)

    dim_df["first_seen_date"] = (
        dim_df["first_seen_date"].dt.date)

    dim_df["latest_seen_date"] = (
        dim_df["latest_seen_date"].dt.date)

    columns = [
        "model_id",
        "model_name",
        "model_creator",
        "canonical_slug",
        "first_seen_date",
        "latest_seen_date",
        "context_length",
        "modality",
        "input_modalities",
        "output_modalities",
        "tokenizer",]

    dim_df = clean_dataframe_for_postgres(dim_df[columns])

    records = []

    for row in dim_df.itertuples(
        index=False,
        name=None,):
        values = list(row)

        if values[6] is not None:
            values[6] = int(values[6])

        records.append(tuple(values))

    return records


def prepare_model_facts(
    model_df: pd.DataFrame,
) -> list[tuple]:
    """Prepare model snapshot fact records."""
    df = model_df.copy()

    df["snapshot_date"] = pd.to_datetime(
        df["snapshot_date"],
        errors="coerce",).dt.date

    df["created_at"] = pd.to_datetime(
        df["created_at"],
        errors="coerce",
        utc=True,)

    df["expiration_date"] = pd.to_datetime(
        df["expiration_date"],
        errors="coerce",).dt.date

    df["knowledge_cutoff"] = pd.to_datetime(
        df["knowledge_cutoff"],
        errors="coerce",).dt.date

    boolean_columns = [
        "reasoning_default_enabled",
        "is_free_model",
        "is_text_to_text",]

    for column in boolean_columns:
        df[column] = df[column].apply(
            to_python_bool)

    columns = [
        "snapshot_date",
        "model_id",
        "canonical_slug",
        "prompt_price_per_1m",
        "prompt_price_status",
        "completion_price_per_1m",
        "completion_price_status",
        "input_cache_read_price_per_1m",
        "input_cache_read_price_status",
        "input_cache_write_price_per_1m",
        "input_cache_write_price_status",
        "request_price",
        "context_length",
        "modality",
        "reasoning_default_enabled",
        "is_free_model",
        "is_text_to_text",
        "created_at",
        "expiration_date",
        "knowledge_cutoff",
        "max_completion_tokens",]

    df = clean_dataframe_for_postgres(
        df[columns])

    records = []

    for row in df.itertuples(
        index=False,
        name=None,):
        values = list(row)

        if values[12] is not None:
            values[12] = int(values[12])

        if values[20] is not None:
            values[20] = int(values[20])

        if values[17] is not None:
            values[17] = values[17].to_pydatetime()

        records.append(tuple(values))

    return records


def prepare_benchmark_facts(
    benchmark_df: pd.DataFrame,
) -> list[tuple]:
    """Prepare benchmark snapshot fact records."""
    df = benchmark_df.copy()

    df["snapshot_date"] = pd.to_datetime(
        df["snapshot_date"],
        errors="coerce",).dt.date

    df["benchmark_as_of"] = pd.to_datetime(
        df["benchmark_as_of"],
        errors="coerce",
        utc=True,)

    columns = [
        "snapshot_date",
        "benchmark_record_id",
        "source",
        "model_key",
        "benchmark_as_of",
        "benchmark_version",
        "display_name",
        "intelligence_index",
        "coding_index",
        "agentic_index",
        "benchmark_prompt_price_per_1m",
        "benchmark_completion_price_per_1m",]

    df = clean_dataframe_for_postgres(
        df[columns])

    records = []

    for row in df.itertuples(
        index=False,
        name=None,):
        values = list(row)

        if values[4] is not None:
            values[4] = values[4].to_pydatetime()

        records.append(tuple(values))

    return records


def prepare_workloads(
    workload_df: pd.DataFrame,
) -> list[tuple]:
    """Prepare workload dimension records."""
    columns = [
        "workload_profile",
        "input_tokens",
        "output_tokens",
        "capability_metric",
        "use_case",]

    df = clean_dataframe_for_postgres(workload_df[columns].copy())

    records = []

    for row in df.itertuples(
        index=False,
        name=None,):
        values = list(row)

        if values[1] is not None:
            values[1] = int(values[1])

        if values[2] is not None:
            values[2] = int(values[2])

        records.append(tuple(values))

    return records


def load_to_postgresql(
    database_url: str,
    model_dimension: list[tuple],
    model_facts: list[tuple],
    benchmark_facts: list[tuple],
    workloads: list[tuple],
) -> None:
    """Load processed data into PostgreSQL."""
    logger.info("Connecting to PostgreSQL.")

    with psycopg.connect(database_url) as connection:
        with connection.cursor() as cursor:

            logger.info("Loading model dimension.")

            cursor.executemany("""INSERT INTO dim_model (
                    model_id,
                    model_name,
                    model_creator,
                    canonical_slug,
                    first_seen_date,
                    latest_seen_date,
                    current_context_length,
                    current_modality,
                    current_input_modalities,
                    current_output_modalities,
                    current_tokenizer
                )
                VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (model_id)
                DO UPDATE SET
                    model_name = EXCLUDED.model_name,
                    model_creator = EXCLUDED.model_creator,
                    canonical_slug = EXCLUDED.canonical_slug,
                    first_seen_date =
                        LEAST(
                            dim_model.first_seen_date,
                            EXCLUDED.first_seen_date),
                    latest_seen_date =
                        GREATEST(
                            dim_model.latest_seen_date,
                            EXCLUDED.latest_seen_date),
                    current_context_length = EXCLUDED.current_context_length,
                    current_modality = EXCLUDED.current_modality,
                    current_input_modalities = EXCLUDED.current_input_modalities,
                    current_output_modalities = EXCLUDED.current_output_modalities,
                    current_tokenizer = EXCLUDED.current_tokenizer;""",model_dimension,)

            logger.info("Loading model snapshots")

            cursor.executemany(
                """
                INSERT INTO fact_model_snapshot (
                    snapshot_date,
                    model_id,
                    canonical_slug,
                    prompt_price_per_1m,
                    prompt_price_status,
                    completion_price_per_1m,
                    completion_price_status,
                    input_cache_read_price_per_1m,
                    input_cache_read_price_status,
                    input_cache_write_price_per_1m,
                    input_cache_write_price_status,
                    request_price,
                    context_length,
                    modality,
                    reasoning_default_enabled,
                    is_free_model,
                    is_text_to_text,
                    created_at,
                    expiration_date,
                    knowledge_cutoff,
                    max_completion_tokens)
                VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s
                )
                ON CONFLICT (
                    snapshot_date,
                    model_id)
                DO UPDATE SET
                    canonical_slug = EXCLUDED.canonical_slug,
                    prompt_price_per_1m = EXCLUDED.prompt_price_per_1m,
                    prompt_price_status = EXCLUDED.prompt_price_status,
                    completion_price_per_1m = EXCLUDED.completion_price_per_1m,
                    completion_price_status = EXCLUDED.completion_price_status,
                    input_cache_read_price_per_1m = EXCLUDED.input_cache_read_price_per_1m,
                    input_cache_read_price_status = EXCLUDED.input_cache_read_price_status,
                    input_cache_write_price_per_1m = EXCLUDED.input_cache_write_price_per_1m,
                    input_cache_write_price_status = EXCLUDED.input_cache_write_price_status,
                    request_price = EXCLUDED.request_price,
                    context_length = EXCLUDED.context_length,
                    modality = EXCLUDED.modality,
                    reasoning_default_enabled = EXCLUDED.reasoning_default_enabled,
                    is_free_model = EXCLUDED.is_free_model,
                    is_text_to_text = EXCLUDED.is_text_to_text,
                    created_at = EXCLUDED.created_at,
                    expiration_date = EXCLUDED.expiration_date,
                    knowledge_cutoff = EXCLUDED.knowledge_cutoff,
                    max_completion_tokens = EXCLUDED.max_completion_tokens;""",model_facts,)

            logger.info("Loading benchmark snapshots.")

            cursor.executemany("""INSERT INTO fact_benchmark_snapshot (
                    snapshot_date,
                    benchmark_record_id,
                    source,
                    model_key,
                    benchmark_as_of,
                    benchmark_version,
                    display_name,
                    intelligence_index,
                    coding_index,
                    agentic_index,
                    benchmark_prompt_price_per_1m,
                    benchmark_completion_price_per_1m)
                VALUES (
                    %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s)
                ON CONFLICT (
                    snapshot_date,
                    benchmark_record_id)
                DO UPDATE SET
                    source = EXCLUDED.source,
                    model_key = EXCLUDED.model_key,
                    benchmark_as_of = EXCLUDED.benchmark_as_of,
                    benchmark_version = EXCLUDED.benchmark_version,
                    display_name = EXCLUDED.display_name,
                    intelligence_index = EXCLUDED.intelligence_index,
                    coding_index = EXCLUDED.coding_index,
                    agentic_index = EXCLUDED.agentic_index,
                    benchmark_prompt_price_per_1m = EXCLUDED.benchmark_prompt_price_per_1m,
                    benchmark_completion_price_per_1m = EXCLUDED.benchmark_completion_price_per_1m;""", benchmark_facts,)

            logger.info("Loading workload assumptions.")

            cursor.executemany("""INSERT INTO dim_workload (
                    workload_profile,
                    input_tokens,
                    output_tokens,
                    capability_metric,
                    use_case)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (
                    workload_profile)
                DO UPDATE SET
                    input_tokens = EXCLUDED.input_tokens,
                    output_tokens = EXCLUDED.output_tokens,
                    capability_metric = EXCLUDED.capability_metric,
                    use_case = EXCLUDED.use_case;""", workloads,)

    logger.info("PostgreSQL transaction completed.")

def main() -> None:
    """Load processed datasets into PostgreSQL."""
    logger.info("Starting PostgreSQL data load.")

    database_url = get_database_url()

    (model_df,
     benchmark_df,
     workload_df,) = load_processed_data()

    validate_input_data(
        model_df,
        benchmark_df,
        workload_df,)

    model_dimension = prepare_model_dimension(model_df)

    model_facts = prepare_model_facts(model_df)

    benchmark_facts = prepare_benchmark_facts(benchmark_df)

    workload_records = prepare_workloads(workload_df)

    load_to_postgresql(
        database_url=database_url,
        model_dimension=model_dimension,
        model_facts=model_facts,
        benchmark_facts=benchmark_facts,
        workloads=workload_records,)

    logger.info("PostgreSQL data load completed successfully.")

    logger.info(
        "Models loaded: %d",
        len(model_dimension),)

    logger.info(
        "Model snapshot rows processed: %d",
        len(model_facts),)

    logger.info(
        "Benchmark rows processed: %d",
        len(benchmark_facts),)

    logger.info(
        "Workload rows processed: %d",
        len(workload_records),)
if __name__ == "__main__":
    main()