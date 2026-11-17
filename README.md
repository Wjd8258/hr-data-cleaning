# HR Data Cleaning & Analytics (MySQL)

Cleaning and analyzing a messy, multi-source HR payroll dataset — from raw CSVs with inconsistent formats, duplicates, and entry errors to a validated analysis view and four business questions answered in SQL.

**Course:** DSCI 6600 Data Wrangling with SQL, M.S. in Artificial Intelligence, Hawaii Pacific University (2026)
**Author:** Jiadi Wu
**Tools:** MySQL 8.0+, DBeaver

## The data

Four course-provided source files, loaded as-is into staging tables before any cleaning:

| File | Contents | Notes |
| --- | --- | --- |
| `companies.csv` | Company / site info | Comma-separated |
| `employees.CSV` | Employee basics (gender, age) | Semicolon-separated |
| `functions.csv` | Job title ↔ function group lookup | Comma-separated |
| `salaries.csv` | Monthly pay details, **8,049 rows** | Semicolon-separated |

The source data is Brazilian-format: salaries use a comma as the decimal separator, and dates are `dd/mm/yyyy hh:mm`. **Data source:** the four CSVs come from the public dataset in [danmarques-dt/SQL_data_cleaning_and_analysis_employees](https://github.com/danmarques-dt/SQL_data_cleaning_and_analysis_employees), where the raw files can also be downloaded — they are not duplicated in this repo. The cleaning and analysis here are my own work, and the decisions differ from the source repo's approach: missing salaries are kept as `NULL` rather than deleted, outliers are flagged (`is_outlier = 1`) rather than deleted, and duplicates are removed with `DISTINCT` instead of a window function.

## Pipeline

The script [`hr_data_wrangling.sql`](hr_data_wrangling.sql) runs in seven stages:

0. **Stage** — create the database and staging tables with loose `VARCHAR` types, load the four CSVs untouched so before/after can be compared and audited.
1. **Assess** — diagnostic queries to find every data quality problem before touching anything.
2. **Clean** — an 8-step cleaning flow producing `companies_clean`, `employees_clean`, `functions_clean`, and `salaries_clean`.
3. **Integrate** — join the four clean tables into one analysis view, `payroll_fact`, so every analysis query reads from a single source.
4. **Validate** — row-count reconciliation, referential-integrity checks, value-domain checks, and salary-range checks.
5. **Analyze** — four business questions (below).
6. **Export** — result sets exported to CSV (in [`outputs/`](outputs/)).

## Data quality issues found (and how they were handled)

- **186 exact duplicate rows** in `salaries.csv` (same employee, month, role, and pay appearing twice) — removed with `DISTINCT`. 8,049 → 7,863 rows, reconciled in validation.
- **70 rows with missing salary** — kept as `NULL` instead of deleting the row, so `AVG`/`SUM` skip them without bias and the full employee-month-role history is preserved.
- **6 outlier rows at 1,000,000** — three orders of magnitude above every other salary, clustered at one site in one month: a data-entry error (three extra zeros). Flagged `is_outlier = 1`, excluded from analysis (`salary_amount = NULL`), raw value kept in `salary_raw` for audit.
- **Spelling errors** — `Goianiaa` → `Goiania`, `Commerciall` → `Commercial`, `Construction Site s` / `Construction Sites` → `Construction Site`, `GOIAS` → `Goias`.
- **Unreliable join keys** — `comp_code = '1'` maps to 15 different company/site names, so it cannot identify a company; the unreliable `comp_code_emp` field in `employees` was dropped and joins use company name instead.
- **Comma decimal separator** — salaries stored as e.g. `1.738,45` converted to standard decimal with `REPLACE(..., ',', '.')` and cast to `DECIMAL(12,2)`.
- **Name mismatches** — 2 employees have different names in `salaries` vs `employees`; the `employees` table was treated as the authoritative source and the discrepancy noted in the report.
- **Structural nulls, not missing data** — empty `const_site_category` for Administration / Development Center sites is a legitimate "no site category" state, labeled explicitly as `N/A` rather than treated as missing.

## Findings

**Q1 — How did pay change over time?** 13 months (Jan 2022 – Jan 2023). Average monthly salary stayed in a narrow band (~1,630–1,740), while monthly headcount paid rose from ~518 to ~660. ([`q1_salary_trend_over_time.csv`](outputs/q1_salary_trend_over_time.csv))

**Q2 — Which function group earns most / least?** Managers average the most (4,138.19, n = 8 employees), followed by Engineering (3,373.84). Trainees earn the least — a flat 950.00. ([`q2_avg_salary_by_function_group.csv`](outputs/q2_avg_salary_by_function_group.csv))

**Q3 — Where is the gender pay gap largest?** By company: The Villas at Hunter's Glen, +1,153.00 (male average above female); DM Company Administration Center is the largest gap in the other direction, −519.86. By function group: Managers, +3,282.05 — by far the largest gap; Trainees show no gap (950.00 for both). ([`q3a_gender_pay_gap_by_company.csv`](outputs/q3a_gender_pay_gap_by_company.csv), [`q3b_gender_pay_gap_by_function_group.csv`](outputs/q3b_gender_pay_gap_by_function_group.csv))

**Q4 — How does pay vary by state?** Goias averages the most (1,671.93, 732 employees), ahead of Distrito Federal (1,649.26) and Tocantins (1,626.54). ([`q4_salary_distribution_by_state.csv`](outputs/q4_salary_distribution_by_state.csv))

## How to run

1. MySQL 8.0+ and DBeaver (or any MySQL client).
2. Update the four `LOAD DATA LOCAL INFILE` paths in Part 0 to point at your copies of `companies.csv`, `employees.CSV`, `functions.csv`, and `salaries.csv`. The script needs `local_infile` enabled (`SET GLOBAL local_infile = 1;` — requires admin privileges).
3. Run the script top to bottom. Parts 1 and 4 are diagnostic/validation queries — read their output before moving on.
4. In DBeaver, run each query in Part 5 and export the result set as CSV (right-click → Export resultset) to reproduce the files in `outputs/`.

## Repo layout

```
hr-data-cleaning/
├── README.md
├── hr_data_wrangling.sql   # full pipeline: stage → assess → clean → integrate → validate → analyze
└── outputs/
    ├── q1_salary_trend_over_time.csv
    ├── q2_avg_salary_by_function_group.csv
    ├── q3a_gender_pay_gap_by_company.csv
    ├── q3b_gender_pay_gap_by_function_group.csv
    └── q4_salary_distribution_by_state.csv
```
