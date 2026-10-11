import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

BASE_URL = "https://openrouter.ai/api/v1"
REQUEST_TIMEOUT = 30

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw" / "openrouter"


def get_api_key() -> str:
    """Load the OpenRouter API key from the local environment."""
    load_dotenv(PROJECT_ROOT / ".env")

    api_key = os.getenv("OPENROUTER_API_KEY", "").strip()

    if not api_key:
        raise ValueError(
            "OPENROUTER_API_KEY is missing. Check the .env file."
        )

    return api_key


def fetch_openrouter_endpoint(endpoint: str, api_key: str) -> dict:
    """Fetch a JSON response from an OpenRouter API endpoint."""
    url = f"{BASE_URL}{endpoint}"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }

    response = requests.get(
        url,
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )

    response.raise_for_status()

    return response.json()


def save_snapshot(data: dict, file_path: Path) -> None:
    """Save a raw API response as a JSON snapshot."""
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with file_path.open("w", encoding="utf-8") as file:
        json.dump(
            data,
            file,
            indent=2,
            ensure_ascii=False,
        )


def run_ingestion() -> None:
    """Fetch and save the daily OpenRouter model and benchmark snapshots."""
    api_key = get_api_key()

    snapshot_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    output_dir = RAW_DATA_DIR / snapshot_date

    logging.info("Starting OpenRouter data ingestion.")

    # Fetch model metadata and pricing.
    models_data = fetch_openrouter_endpoint("/models", api_key)

    models_file = output_dir / "models.json"
    save_snapshot(models_data, models_file)

    model_list = models_data.get("data", [])

    logging.info(
        "Saved %d models to %s",
        len(model_list),
        models_file,
    )

    # Fetch benchmark metadata.
    benchmarks_data = fetch_openrouter_endpoint("/benchmarks", api_key)

    benchmarks_file = output_dir / "benchmarks.json"
    save_snapshot(benchmarks_data, benchmarks_file)

    benchmark_list = benchmarks_data.get("data", [])

    logging.info(
        "Saved %d benchmark records to %s",
        len(benchmark_list),
        benchmarks_file,
    )

    logging.info(
        "OpenRouter ingestion completed successfully for %s.",
        snapshot_date,
    )


if __name__ == "__main__":
    try:
        run_ingestion()
    except Exception:
        logging.exception("OpenRouter ingestion failed.")
        raise