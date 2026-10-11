# AI-FinOps: LLM Cost, Performance & Optimization Analytics

![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white) ![Pandas](https://img.shields.io/badge/Pandas-2.x-150458?logo=pandas&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16%2B-4169E1?logo=postgresql&logoColor=white) ![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?logo=tableau&logoColor=white)

**Case Study Overview**

A manually refreshable data analytics case study that evaluates LLM pricing, benchmark-based capability and workload-level cost trade-offs using dated public OpenRouter data.

**Live Tableau Dashboard:** [View Published Dashboards](https://public.tableau.com/views/ai-finops-llm-cost-performance-optimization/ExecutiveOverview?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_linkL)

## Business Problem

Organizations adopting LLMs face a model-selection challenge: **which model provides the capability a workload needs at a sensible cost?** Choosing only on price can reduce capability, while defaulting to premium models can create unnecessary inference spend.

## Analysis Scope

The published Tableau dashboards reflect the **6 October 2026 analysis snapshot**. The project analysis and refresh cycle also includes the **5 October pricing baseline** and the **7 October refresh check**, which helped assess catalog movement, benchmark coverage and pipeline consistency around the published dashboard period.

Because the project is manually refreshable, the figures in the dashboards and this documentation are dated market views rather than real-time figures.

## Data Source

**Primary source:** OpenRouter public API

The project captures dated snapshots of model metadata, pricing, context/modality information and available benchmark capability data.

Capability analysis uses OpenRouter's:

- Intelligence Index
- Coding Index
- Agentic Index

## Analytical Workflow

```text
OpenRouter public API
        ↓
Python / Pandas
        ↓
Cleaning + validation
        ↓
PostgreSQL
        ↓
SQL analytics
        ↓
10 reporting datasets
        ↓
Tableau dashboards
```

A manual refresh runs the end-to-end pipeline with one command:

```powershell
python .\scripts\run_pipeline.py
```

The pipeline performs OpenRouter ingestion, transformation, validation, PostgreSQL loading, reporting-dataset generation and 10 reporting datasets refresh.

The published Tableau dashboards use the stable CSV reporting layer generated for the **6 October 2026 analysis**.

## Data Model

PostgreSQL is the analytical storage layer. The core model contains:

- `dim_model` — model-level attributes and model history dates
- `fact_model_snapshot` — dated pricing and model metadata snapshots
- `fact_benchmark_snapshot` — dated benchmark and capability records
- `dim_workload` — workload profiles, token assumptions and capability targets

The snapshot design preserves dated history so pricing and model movement can be analysed across refreshes.

## SQL Analysis

The SQL layer uses joins, CTEs, window functions, percentiles and ranking to produce decision-focused datasets covering market/pricing mix, benchmark coverage, capability, workload cost, paid-model comparisons and the cost-capability frontier.

## Key Findings

The combined **5-7 October 2026 analysis cycle** is more useful than treating any single snapshot as a permanent market view:

- **The market stayed in the mid-460s, but the catalog was not static.** The 5 October pricing baseline contained **466 models**; the 7 October refresh had **465 current models** and identified **2 new and 1 removed model** versus the prior snapshot. The 6 October dashboards therefore represent a dated decision view rather than a permanent ranking.
- **Pricing alone does not answer the model-selection question.** On 5 October, **437 of 466 models (93.78%) were priced**, 22 were free (4.72%) and 7 were pricing exceptions (1.50%). The 6 October workload analysis showed why free or low-cost models should still be assessed against the capability required for each workload.
- **Capability evidence is incomplete and workload-specific.** The 7 October refresh recorded a **62.44% benchmark-key match rate**. Across the six workload profiles analysed on 6 October, the relevant capability metric and token assumptions changed by use case, so the sensible decision is to shortlist models that meet the workload requirement at an acceptable cost rather than choose one global winner.
- **The practical decision rule is cost + capability + evidence.** A low listed price is useful only when the model has enough capability for the workload and sufficient evidence to support the comparison.

## Recommendations

1. **Set the required capability by workload first, then compare cost** among models that meet the requirement.
2. **Use a two-tier routing approach:** favor lower-cost qualifying models for routine workloads and reserve higher-capability, higher-cost options for workloads where the uplift is justified.
3. **Use benchmark coverage and pricing status as confidence gates** before a model is included in a business recommendation.
4. **Use the cost-capability frontier as a shortlist, not a permanent winner**, and revisit the decision when pricing or model availability changes.

## Tableau Dashboards

### Executive Overview

Market view covering model mix, pricing status, creator concentration and broad model characteristics.

### Model Efficiency

Compares estimated workload cost with relevant capability to highlight efficient model options.

### Optimization Analysis

Focuses on workload-specific alternatives, paid-model comparisons, cost rankings and the cost-capability frontier.

## Refresh Workflow

The project is designed for a **manual, repeatable refresh** rather than an always-on service.

```text
python .\scripts\run_pipeline.py
        ↓
OpenRouter snapshot
        ↓
Python transformation + validation
        ↓
PostgreSQL
        ↓
10 reporting datasets

```

The six SQL-derived reporting datasets are regenerated from PostgreSQL, so their CSV outputs no longer need to be manually downloaded after each refresh.

## Data Quality & Limitations

The validation layer checks duplicate keys, invalid values, pricing exceptions, missing model keys, workload assumptions, benchmark coverage and model movement.

Key limitations:

- Benchmark coverage is incomplete; capability comparisons apply where usable benchmark data is available.
- Benchmark scores are source-specific and time-specific indicators, not universal measures of real-world quality.
- Free and pricing-exception models require careful interpretation in cost comparisons.

## Tools

| Area             | Tool                  |
| ---------------- | --------------------- |
| Data source      | OpenRouter public API |
| Data preparation | Python, Pandas        |
| Database         | PostgreSQL            |
| Analytics        | SQL                   |
| BI               | Tableau Public        |
| Version control  | Git / GitHub          |

## Repository Structure

```text
ai-finops-llm-cost-performance-optimization/
│
├── data/          # raw OpenRouter snapshots + processed reporting datasets
├── database/      # PostgreSQL schema and analytics SQL
├── scripts/       # ingestion, transformation, validation, loading and refresh pipeline
├── dashboard/     # Tableau workbook and dashboard screenshots
├── docs/          # case-study documentation
├── .env.example
├── requirements.txt
└── README.md
```

## Running the Project

1. Create a local Python environment.
2. Install the dependencies from `requirements.txt`.
3. Configure the required local environment variables using `.env.example`.
4. Configure the local PostgreSQL database.
5. Run:

```powershell
python .\scripts\run_pipeline.py
```

API keys and PostgreSQL credentials files are kept out of the repository.

## Outcome

AI-FinOps turns changing public LLM market data into a structured decision view across **cost, capability and workload fit**. The main business takeaway is that model selection should be treated as a workload-specific cost-capability decision rather than a simple cheapest-price ranking.
