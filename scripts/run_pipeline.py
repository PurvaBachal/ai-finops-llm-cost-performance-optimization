from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent

STEPS = [
    ("OpenRouter ingestion", "fetch_openrouter.py"),
    ("Data transformation", "transform_data.py"),
    ("Data validation", "validate_data.py"),
    ("PostgreSQL load", "load_postgres.py"),
    ("Tableau dataset export", "export_tableau_data.py"),
]

def run_step(name, script):
    print(f"\n--- {name} ---")
    script_path = ROOT / script
    
    if not script_path.exists():
        raise FileNotFoundError(f"Script not found: {script_path}")
        
    subprocess.run([sys.executable, str(script_path)], check=True)

def main():
    for name, script in STEPS:
        run_step(name, script)
        
    print("\nAI-FinOps pipeline refresh completed successfully.")

if __name__ == "__main__":
    main()