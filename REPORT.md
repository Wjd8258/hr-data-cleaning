# HR Data Cleaning & Analytics — Project Report

**Final Project: Data Wrangling with SQL — Project Report**

**Author:** Jiadi Wu

**Course:** DSCI 6600 Data Wrangling with SQL

**Database:** MySQL 8.0 (DBeaver) | **Data sources:** companies.csv, employees.CSV, functions.csv, salaries.csv — from the public dataset in [danmarques-dt/SQL_data_cleaning_and_analysis_employees](https://github.com/danmarques-dt/SQL_data_cleaning_and_analysis_employees)

## 1. Project Overview

This project uses MySQL (executed in DBeaver) to clean, integrate, and analyze a human-resources dataset provided by a company. The dataset consists of four source tables: company/site information (`companies`), employee basics (`employees`), a job-title-to-function-group lookup (`functions`), and monthly pay details (`salaries`, 8,049 rows). The project follows a standard 8-step data cleaning process, builds one integrated wide table for analysis, and answers four business questions:

- How did pay change over time?
- Which function group has the highest / lowest average salary?
- Which company / function group has the largest gender pay gap?
- How is pay distributed across states?

The full executable MySQL script is in the companion file `hr_data_wrangling.sql`, and the query results for the four questions were exported as CSV files (q1–q4).

## 2. Data Quality Assessment

Before cleaning, each of the four source tables was examined with diagnostic queries (Part 1 of the script). The problems found:

### 2.1 companies (company / site table, 25 rows)

- **Spelling / structural errors:** city "Goianiaa" should be "Goiania"; company type "Construction Site s" and "Construction Sites" should both be "Construction Site"; site category "Commerciall" should be "Commercial".
- **Missing values:** 4 rows have an empty `const_site_category`, all of them Administration / Development Center types. This is a structural null, not true missing data — these companies are not construction sites and have no site category.

### 2.2 employees (employee table, 1,156 rows)

- The `comp_code_emp` field (employee's company code) is unreliable: its values are inconsistent, including the non-numeric value "ELMO", and its value set does not fully match `comp_code` in the salaries table.
- Gender and age are clean, with no missing values and no outliers (age range 18–42).

### 2.3 functions (job-title lookup table, 107 rows)

No duplicates, no missing values, and no formatting problems. There are 8 function groups: Managers, Engineering, Production Supervisors, Administration, Machine Operators, Professionals, Assistants, Trainees.

### 2.4 salaries (pay detail table, 8,049 rows — the most problematic)

- **Join-key problem:** `comp_code` cannot uniquely identify a company — for example, `comp_code = '1'` corresponds to 15 different company/site names, suggesting the code is used as a placeholder in the source system. It is not suitable as a join key; company name (`comp_name`) should be used to join to the companies table instead.
- **Duplicate records:** 186 fully duplicated rows (the same employee, month, role, and salary appearing twice or more).
- **Missing values:** 70 rows have an empty salary, concentrated in Young Apprentice, Office Assistant, Bricklayer B, and similar roles.
- **Inconsistent formats:** salary values use a comma as the decimal separator (e.g., "6335,56") and must be converted to standard decimal format; the date field is a string such as "01/01/2022 00:00", where the day is always 01 and represents the pay month.
- **Outliers:** 6 deduplicated records have a salary of 1,000,000 — about three orders of magnitude above every other salary — all concentrated at one site (The Sanctuary at Briarcliff), on one day (2023-01-01), across several General Services Assistants. This is a batch data-entry error (three extra zeros).
- **Cross-table check:** comparing `salaries.employee_name` with `employees.employee_name_emp` by `employee_id` found 2 employees whose names differ between the tables. The employees table was judged the authoritative source for employee names.

## 3. Data Cleaning: the 8-Step Process

The steps below follow the project's standard 8-step cleaning flow, applied table by table (full SQL in Part 2 of the script):

1. **Remove irrelevant data:** dropped the unreliable `comp_code_emp` field from employees; salaries no longer keeps the redundant company code or the company/role text fields that can be obtained by joining the dimension tables — only business keys and measures remain.
2. **Remove duplicates:** applied `DISTINCT` across all fields on the original 8,049 salary rows, removing 186 fully duplicated records and leaving 7,863 rows.
3. **Fix structural errors:** corrected the spelling errors in the companies table (Goianiaa / Construction Site s / Construction Sites / Commerciall).
4. **Convert types:** replaced the comma with a period in salary values and converted them to `DECIMAL(12,2)`; parsed date strings into standard `DATE` values with `STR_TO_DATE`; converted employee IDs, function codes, and similar fields to integers.
5. **Handle missing values:** the 70 rows with missing salary were kept, with the salary field set to `NULL`. Aggregate functions (`AVG`/`SUM`) automatically skip `NULL`, so the statistics are unaffected, while each employee's complete monthly history is preserved instead of losing information by deleting whole rows.
6. **Standardize / normalize:** unified state-name casing (e.g., "GOIAS" → "Goias"), unified company-type values, standardized gender to uppercase M/F, and trimmed leading/trailing whitespace from all text fields.
7. **Handle outliers:** the 6 records with a salary of 1,000,000 were flagged as outliers (`is_outlier = 1`), and the analysis field `salary_amount` was set to `NULL` for them (excluded from averages and totals). The original erroneous value is kept in the `salary_raw` field for audit traceability. This is a conservative treatment — no subjective "guessed correction" was applied, to avoid introducing new bias.
8. **Validate:** reconciled row counts before and after cleaning (8,049 → 7,863, a difference of 186 that matches the duplicate count); checked foreign-key integrity between `salaries_clean` and the three dimension tables (no orphan records); checked that the value domains for gender, state, and company type had converged to the expected finite sets; and checked that the cleaned salary range was reasonable (no negative values, no remaining outliers).

After cleaning, the four tables are joined on company name, employee ID, and function code into the analysis view `payroll_fact`, the single data source for all subsequent analysis queries.

## 4. Analysis Results

### 4.1 Salary trend over time

**SQL:**

```sql
SELECT pay_month,
       COUNT(*) AS employee_payments,
       ROUND(AVG(salary_amount), 2) AS avg_salary,
       ROUND(SUM(salary_amount), 2) AS total_payroll
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY pay_month
ORDER BY pay_month;
```

**Results** — average salary and total payroll by pay month (Jan 2022 – Jan 2023, 13 months):

| Pay month | Payments | Avg salary | Total payroll |
| --- | --- | --- | --- |
| 2022-01 | 518 | 1738.45 | 900,516.94 |
| 2022-02 | 520 | 1730.72 | 899,972.45 |
| 2022-03 | 519 | 1705.52 | 885,164.53 |
| 2022-04 | 602 | 1662.31 | 1,000,712.40 |
| 2022-05 | 611 | 1669.04 | 1,019,784.65 |
| 2022-06 | 627 | 1651.53 | 1,035,510.70 |
| 2022-07 | 600 | 1636.57 | 981,942.16 |
| 2022-08 | 620 | 1635.83 | 1,014,211.56 |
| 2022-09 | 633 | 1638.33 | 1,037,059.74 |
| 2022-10 | 592 | 1658.47 | 981,815.73 |
| 2022-11 | 660 | 1644.34 | 1,085,262.79 |
| 2022-12 | 643 | 1632.45 | 1,049,664.23 |
| 2023-01 | 642 | 1643.09 | 1,054,866.66 |

**Observation:** average monthly salary drifted slowly downward over the period and then stabilized (from about 1,738 at the start of 2022 to the 1,630–1,660 range by the end of the year), while total payroll rose from roughly 900,000 a month to over 1,000,000. That increase was driven by headcount growth — monthly pay records rose from 518 to around 660 — not by rising average pay. In other words, the company grew faster than its average salary did.

### 4.2 Average salary by function group

**SQL:**

```sql
SELECT function_group,
       COUNT(*) AS num_payments,
       COUNT(DISTINCT employee_id) AS num_employees,
       ROUND(AVG(salary_amount), 2) AS avg_salary,
       ROUND(MIN(salary_amount), 2) AS min_salary,
       ROUND(MAX(salary_amount), 2) AS max_salary
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY function_group
ORDER BY avg_salary DESC;
```

**Results:**

| Function group | Payments | Employees | Avg salary | Min salary | Max salary |
| --- | --- | --- | --- | --- | --- |
| Managers | 80 | 8 | 4138.19 | 1348.44 | 6335.56 |
| Engineering | 193 | 19 | 3373.84 | 2596.77 | 5500.00 |
| Production Supervisors | 373 | 45 | 2847.74 | 1120.00 | 5612.90 |
| Administration | 654 | 86 | 1963.50 | 606.00 | 5870.97 |
| Machine Operators | 256 | 33 | 1743.81 | 1036.98 | 2800.00 |
| Professionals | 3290 | 488 | 1705.09 | 1015.55 | 2103.20 |
| Assistants | 2783 | 441 | 1225.90 | 1016.52 | 2103.20 |
| Trainees | 158 | 30 | 950.00 | 950.00 | 950.00 |

**Conclusion:** the highest-paid function group is Managers (average 4,138.19), followed by Engineering (3,373.84). The lowest-paid is Trainees (950.00 — completely flat, with no variation), followed by Assistants (1,225.90). The overall pattern is a clear pay gradient — management / technical roles > production / administrative roles > assistant / trainee roles — consistent with a typical corporate pay structure.

### 4.3 Gender pay gap

**(a) By company** (gap = male average − female average; a positive value means men earn more):

**SQL:**

```sql
SELECT company_name,
       ROUND(AVG(CASE WHEN gender = 'M' THEN salary_amount END), 2) AS avg_salary_male,
       ROUND(AVG(CASE WHEN gender = 'F' THEN salary_amount END), 2) AS avg_salary_female,
       ROUND(
         AVG(CASE WHEN gender = 'M' THEN salary_amount END) -
         AVG(CASE WHEN gender = 'F' THEN salary_amount END), 2
       ) AS gap_male_minus_female
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY company_name
HAVING avg_salary_male IS NOT NULL AND avg_salary_female IS NOT NULL
ORDER BY ABS(gap_male_minus_female) DESC;
```

**Results** (10 of 16 companies shown; the full 16 are in [`q3a_gender_pay_gap_by_company.csv`](outputs/q3a_gender_pay_gap_by_company.csv)):

| Company / site | Avg salary, male | Avg salary, female | Gap (M − F) |
| --- | --- | --- | --- |
| The Villas at Hunter's Glen | 2103.00 | 950.00 | 1153.00 |
| DM Company Administration Center | 1552.95 | 2072.80 | -519.86 |
| The Meadows at Sunset Ridge | 1737.69 | 1339.45 | 398.24 |
| DM Company Development Center | 1528.16 | 1874.79 | -346.62 |
| The Crossings at Falcon Point | 1647.43 | 1370.00 | 277.43 |
| The Glades at Maplewood | 1582.82 | 1319.86 | 262.97 |
| The Landings at Ocean Breeze | 1435.76 | 1272.10 | 163.66 |
| DM Company Head Quarters | 2583.86 | 2712.48 | -128.62 |
| Regional Hospital | 1498.26 | 1620.23 | -121.97 |
| The Terraces at Diamond Heights | 1580.77 | 1696.81 | -116.04 |

The largest gap is at The Villas at Hunter's Glen (men higher by 1,153.00), but the gender sample there is severely unbalanced (61 men vs only 5 women), so the result is easily driven by a few individuals and should be read with caution. The more balanced and more informative cases are DM Company Administration Center (80 men / 14 women, women higher by 519.86) and The Meadows at Sunset Ridge (568 men / 36 women, men higher by 398.24).

**(b) By function group:**

**SQL:**

```sql
SELECT function_group,
       ROUND(AVG(CASE WHEN gender = 'M' THEN salary_amount END), 2) AS avg_salary_male,
       ROUND(AVG(CASE WHEN gender = 'F' THEN salary_amount END), 2) AS avg_salary_female,
       ROUND(
         AVG(CASE WHEN gender = 'M' THEN salary_amount END) -
         AVG(CASE WHEN gender = 'F' THEN salary_amount END), 2
       ) AS gap_male_minus_female
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY function_group
HAVING avg_salary_male IS NOT NULL AND avg_salary_female IS NOT NULL
ORDER BY ABS(gap_male_minus_female) DESC;
```

**Results:**

| Function group | Avg salary, male | Avg salary, female | Gap (M − F) |
| --- | --- | --- | --- |
| Managers | 4630.49 | 1348.44 | 3282.05 |
| Administration | 1906.27 | 2322.15 | -415.88 |
| Production Supervisors | 2836.17 | 2990.33 | -154.16 |
| Machine Operators | 1747.28 | 1679.03 | 68.24 |
| Professionals | 1699.42 | 1741.61 | -42.19 |
| Assistants | 1227.28 | 1218.47 | 8.81 |
| Trainees | 950.00 | 950.00 | 0.00 |

**Conclusion:** the largest gender pay gap by function group is Managers — men average 3,282.05 more than women — but the group has only 8 employees, and the female average is determined by a single person's salary (1,348.44). The sample is far too small to conclude systemic gender discrimination in that group; it is a signal that warrants further investigation. The larger-sample groups, Administration (654 records) and Production Supervisors (373 records), both show women averaging slightly more than men. Overall, apart from Managers, every function group's gender pay gap is within ±420 — relatively mild.

### 4.4 Salary distribution by state

**SQL:**

```sql
SELECT state,
       COUNT(*) AS num_payments,
       COUNT(DISTINCT employee_id) AS num_employees,
       ROUND(AVG(salary_amount), 2) AS avg_salary,
       ROUND(MIN(salary_amount), 2) AS min_salary,
       ROUND(MAX(salary_amount), 2) AS max_salary,
       ROUND(SUM(salary_amount), 2) AS total_payroll
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY state
ORDER BY avg_salary DESC;
```

**Results:**

| State | Payments | Employees | Avg salary | Min salary | Max salary | Total payroll |
| --- | --- | --- | --- | --- | --- | --- |
| Goias | 4865 | 732 | 1671.93 | 606.00 | 6335.56 | 8,133,945.18 |
| Distrito Federal | 2632 | 371 | 1649.26 | 950.00 | 5500.00 | 4,340,841.71 |
| Tocantins | 290 | 50 | 1626.54 | 950.00 | 3884.50 | 471,697.65 |

**Conclusion:** average pay across the three states is very close (1,626–1,672, a spread of under 3%), indicating broadly consistent pay levels across regions with no evident geographic pay imbalance. Goias has the most employees (732, about 63% of the total) and is the company's main base; Tocantins is the smallest (50 employees). Both the highest salary (6,335.56) and the lowest (606.00) occur in Goias, reflecting its complete job structure — from headquarters management roles to frontline positions.

## 5. Conclusions & Recommendations

- **Overall data quality is moderate.** The main problems are concentrated in the pay detail table (duplicates, missing values, inconsistent formats, a batch entry error); the company dimension table has a few spelling errors. All were fixed or flagged appropriately during cleaning.
- **Payroll growth is driven by headcount.** The rise in total payroll is mainly due to company expansion, not average raises; this should be verified against hiring data in follow-up work.
- **The pay gradient is reasonable.** The structure matches the expected pattern of management / technical > production / administrative > assistant / trainee. Trainees are paid a flat 950 with no variation — worth verifying as the standard fixed rate for that role.
- **Gender pay gaps are mild where samples are adequate** (mostly within ±420), but the Managers group and a few small sites have samples too small for their gap figures to be reliable. Any assessment of systemic differences should use a larger sample or a longer time window.
- **No regional imbalance.** Pay levels are close across states; Tocantins is small, so it is worth checking whether its job structure is complete.
- **System improvement:** the batch entry error of 1,000,000 should be reported back to the source data-entry system, and the affected payroll batch (The Sanctuary at Briarcliff, 2023-01) should be checked for any other undetected errors.

## 6. Attachments

- `hr_data_wrangling.sql` — the complete, executable data cleaning and analysis SQL script (with comments), runnable in DBeaver / MySQL
- This report — data quality assessment, the 8-step cleaning process, the SQL for each analysis question, and the query outputs
- `q1_salary_trend_over_time.csv` — results for Question 1
- `q2_avg_salary_by_function_group.csv` — results for Question 2
- `q3a_gender_pay_gap_by_company.csv` / `q3b_gender_pay_gap_by_function_group.csv` — results for Question 3
- `q4_salary_distribution_by_state.csv` — results for Question 4
