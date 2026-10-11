import os
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATABASE_DIR = PROJECT_ROOT / "database"
OUTPUT_DIR = PROJECT_ROOT / "data" / "processed" 


EXPORTS = [
    {
        "output": "model_efficiency.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 2,
    },
    {
        "output": "workload_comaparison.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 3,
    },
    {
        "output": "paid_workload_comparison.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 4,
    },
    {
        "output": "optimization_frontier.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 5,
    },
    {
        "output": "top_cost_optimization.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 7,
    },
    {
        "output": "paid_cost_alternatives.csv",
        "sql_file": "04_optimization_analytics.sql",
        "statement_number": 8,
    },
]

def get_database_url() -> str:
    """Load the existing PostgreSQL connection string."""

    load_dotenv(PROJECT_ROOT / ".env")

    database_url = os.getenv("DATABASE_URL", "").strip()

    if not database_url:
        raise ValueError(
            "DATABASE_URL is missing from the .env file."
        )

    return database_url


def load_sql_statement(
    sql_file: str,
    statement_number: int,
) -> str:

    sql_path = DATABASE_DIR / sql_file

    if not sql_path.exists():
        raise FileNotFoundError(
            f"SQL file not found: {sql_path}"
        )

    sql_text = sql_path.read_text(encoding="utf-8")

    statements = [
        statement.strip()
        for statement in sql_text.split(";")
        if statement.strip()
    ]

    if statement_number > len(statements):
        raise IndexError(
            f"Statement {statement_number} not found in "
            f"{sql_file}. Found {len(statements)} statements."
        )

    return statements[statement_number - 1]


def execute_query(
    connection,
    sql: str,
) -> pd.DataFrame:
    """Execute SQL and return the result as a DataFrame."""

    with connection.cursor() as cursor:
        cursor.execute(sql)

        rows = cursor.fetchall()
        columns = [column.name for column in cursor.description]

    return pd.DataFrame(rows, columns=columns)


def export_query(
    connection,
    export_config: dict,
) -> None:
    """Run one existing SQL statement and save its result."""

    output_name = export_config["output"]
    sql_file = export_config["sql_file"]
    statement_number = export_config["statement_number"]

    print(f"\n--- Exporting {output_name} ---")

    sql = load_sql_statement(
        sql_file=sql_file,
        statement_number=statement_number,
    )

    dataframe = execute_query(
        connection=connection,
        sql=sql,
    )

    output_path = OUTPUT_DIR / output_name

    dataframe.to_csv(
        output_path,
        index=False,
    )

    print(f"Rows exported: {len(dataframe):,}")
    print(f"Columns exported: {len(dataframe.columns):,}")
    print(f"Saved to: {output_path}")


def main() -> None:
    """Generate test copies of the six SQL-derived Tableau datasets."""

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    print("Starting Tableau dataset export.")

    database_url = get_database_url()

    with psycopg.connect(database_url) as connection:
        print("Connected to PostgreSQL.")

        for export_config in EXPORTS:
            export_query(
                connection=connection,
                export_config=export_config,
            )

    print("\nTableau dataset export completed successfully.")


if __name__ == "__main__":
    main()