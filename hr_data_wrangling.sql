/* ============================================================================
   Jiadi Wu
   DSCI 6600 基于结构化查询语言（SQL）的数据整理 
   期末项目1：人力资源数据清洗与分析
   数据库：MySQL 8.0+   工具：DBeaver

   数据源文件（4 张原始表）：
     companies.csv   （逗号分隔，公司/工地信息）
     employees.CSV   （分号分隔，员工基本信息：性别、年龄）
     functions.csv   （逗号分隔，职位与职能组对照表）
     salaries.csv    （分号分隔，逐月工资明细，8049 行）

   本脚本共 7 部分：
     0. 建库、建"原始暂存表"(staging) 并导入数据
     1. 数据质量评估（诊断性查询）
     2. 数据清理 8 步流程 -> 生成"干净表" (clean tables)
     3. 数据整合 -> 生成分析用宽表 (payroll_fact)
     4. 数据验证
     5. 分析查询：回答项目要求的 4 个业务问题
     6. 结果导出说明
   ========================================================================= */


/* ============================================================================
   第 0 部分：建库 & 建原始暂存表 (staging tables)
   目的：先"原样"导入四个 CSV 文件，字段类型尽量宽松 (VARCHAR)，
        保留原始脏数据，方便后续做"清理前 / 清理后"对比与审计。
   ========================================================================= */

CREATE DATABASE IF NOT EXISTS hr_project
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE hr_project;

-- 0.1 companies.csv（逗号分隔，首行表头，UTF-8 BOM）
DROP TABLE IF EXISTS stg_companies;
CREATE TABLE stg_companies (
    company_name          VARCHAR(100),
    company_city          VARCHAR(50),
    company_state         VARCHAR(50),
    company_type          VARCHAR(50),
    const_site_category   VARCHAR(50)
) ENGINE=InnoDB;

-- 0.2 employees.CSV（分号分隔）
DROP TABLE IF EXISTS stg_employees;
CREATE TABLE stg_employees (
    comp_code_emp      VARCHAR(20),
    employee_code_emp  VARCHAR(20),
    employee_name_emp  VARCHAR(100),
    gender_raw         VARCHAR(10),
    age                VARCHAR(10)
) ENGINE=InnoDB;

-- 0.3 functions.csv（逗号分隔）
DROP TABLE IF EXISTS stg_functions;
CREATE TABLE stg_functions (
    function_code    VARCHAR(20),
    function_name    VARCHAR(100),
    function_group   VARCHAR(50)
) ENGINE=InnoDB;

-- 0.4 salaries.csv（分号分隔）
DROP TABLE IF EXISTS stg_salaries;
CREATE TABLE stg_salaries (
    comp_code       VARCHAR(20),
    comp_name       VARCHAR(100),
    employee_id     VARCHAR(20),
    employee_name   VARCHAR(100),
    pay_date_raw    VARCHAR(30),
    func_code       VARCHAR(20),
    func_name       VARCHAR(100),
    salary_raw      VARCHAR(30)
) ENGINE=InnoDB;

-- 导入数据 ----------

   
SET GLOBAL local_infile = 1;
SHOW VARIABLES LIKE 'local_infile';
-- 导入companies.csv 表格   
LOAD DATA LOCAL INFILE '/Users/jiadiwu/Downloads/project 1/companies.csv'
   INTO TABLE stg_companies
   CHARACTER SET utf8mb4
   FIELDS TERMINATED BY ','
   OPTIONALLY ENCLOSED BY '"'
   LINES TERMINATED BY '\n'
   IGNORE 1 ROWS;
-- 展示导入成果
SELECT * FROM stg_companies LIMIT 10;

-- 导入employees.CSV表格 
   LOAD DATA LOCAL INFILE '/Users/jiadiwu/Downloads/project 1/employees.CSV'
   INTO TABLE stg_employees
   CHARACTER SET utf8mb4
   FIELDS TERMINATED BY ';'
   LINES TERMINATED BY '\r\n'
   IGNORE 1 ROWS;
-- 展示导入成果
SELECT * FROM stg_employees LIMIT 10;   

-- 导入functions.csv表格 
   LOAD DATA LOCAL INFILE '/Users/jiadiwu/Downloads/project 1/functions.csv'
   INTO TABLE stg_functions
   CHARACTER SET utf8mb4
   FIELDS TERMINATED BY ','
   LINES TERMINATED BY '\r\n'
   IGNORE 1 ROWS;
-- 展示导入成果
SELECT * FROM stg_functions LIMIT 10

-- 导入salaries.csv表格
   LOAD DATA LOCAL INFILE '/Users/jiadiwu/Downloads/project 1/salaries.csv'
   INTO TABLE stg_salaries
   CHARACTER SET utf8mb4
   FIELDS TERMINATED BY ';'
   LINES TERMINATED BY '\r\n'
   IGNORE 1 ROWS;
SELECT * FROM stg_salaries LIMIT 10
------------------------------------------------------------------------- */


/* ============================================================================
   第 1 部分：数据质量评估 (Assess Data Quality)
   在正式清理前，先用诊断性查询摸清楚数据里都有哪些问题。
   下面这些 SELECT 是诊断用的，执行后人工检查结果，
   本项目中发现的问题总结在书面报告里。
   ========================================================================= */

-- 1.1 companies：查看州、公司类型、工地类别的所有取值，找拼写错误
SELECT DISTINCT company_city FROM stg_companies;
SELECT DISTINCT company_type  FROM stg_companies;
SELECT DISTINCT const_site_category FROM stg_companies;

-- 发现：
--   company_city 中 'Goianiaa' 是 'Goiania' 的拼写错误
--   company_type 中 'Construction Site s' / 'Construction Sites' 都应为 'Construction Site'
--   const_site_category 中 'Commerciall' 应为 'Commercial'；4 行为空（Administration/开发中心本身无工地类别，属结构性正常空值）

-- 1.2 employees：comp_code_emp 是否可靠？
SELECT DISTINCT comp_code_emp FROM stg_employees ORDER BY comp_code_emp;
-- 发现：取值混乱 ('ELMO', '1', '83', '122', '126', '1260' 等)，
-- 且与 salaries.comp_code 的取值集合并不完全一致 -> 该字段不可靠，
-- 不适合作为员工与公司的关联键，判定为"无关/不可靠字段"，第2部分予以剔除。

-- 1.3 salaries：公司编码是否能唯一确定公司？
SELECT comp_code, COUNT(DISTINCT comp_name) AS company_names_per_code
FROM stg_salaries
GROUP BY comp_code
HAVING COUNT(DISTINCT comp_name) > 1;
-- 发现：comp_code = '1' 对应 15 个不同的公司/工地名称！
-- comp_code 不是公司的唯一标识，因此表间关联应使用公司名称 (comp_name / company_name)
-- 而不是 comp_code。

-- 1.4 salaries：重复行
SELECT comp_code, comp_name, employee_id, employee_name, pay_date_raw,
       func_code, func_name, salary_raw, COUNT(*) AS cnt
FROM stg_salaries
GROUP BY comp_code, comp_name, employee_id, employee_name, pay_date_raw,
         func_code, func_name, salary_raw
HAVING COUNT(*) > 1;
-- 发现：186 行完全重复（同一员工同一月份同一职位同一工资出现2次以上）

-- 1.5 salaries：缺失工资
SELECT COUNT(*) AS missing_salary_rows
FROM stg_salaries
WHERE salary_raw IS NULL OR TRIM(salary_raw) = '';
-- 发现：70 行工资为空，集中在 Young Apprentice / Office Assistant / Bricklayer B 等岗位

-- 1.6 salaries：工资格式与异常值
SELECT salary_raw
FROM stg_salaries
WHERE CAST(REPLACE(salary_raw, ',', '.') AS DECIMAL(12,2)) > 100000;
-- 发现：6 条记录（去重后）工资为 1,000,000，明显是多打了 3 个 0 的录入错误
SELECT
    comp_code,
    comp_name,
    employee_id,
    employee_name,
    pay_date_raw,
    func_code,
    func_name,
    salary_raw,
    CAST(REPLACE(salary_raw, ',', '.') AS DECIMAL(12,2)) AS salary_converted
FROM stg_salaries
WHERE CAST(REPLACE(salary_raw, ',', '.') AS DECIMAL(12,2)) > 100000
ORDER BY comp_name, pay_date_raw;
-- （The Sanctuary at Briarcliff 工地，2023-01 当月，多名 General Services Assistant 同时出现）；
-- 工资字段本身用逗号做小数点（巴西/欧洲惯例），需要转换成标准小数格式。

-- 1.7 salaries 与 employees：员工姓名是否一致（交叉校验）
SELECT s.employee_id, s.employee_name AS name_in_salaries,
       e.employee_name_emp AS name_in_employees
FROM (SELECT DISTINCT employee_id, employee_name FROM stg_salaries) s
JOIN stg_employees e ON s.employee_id = e.employee_code_emp
WHERE s.employee_name <> e.employee_name_emp;
-- 发现：2 名员工在两张表中姓名不一致，判定 employees 表为员工主数据来源（更权威），
-- 在最终整合中以 employees 表姓名为准，并在报告中注明该不一致。


/* ============================================================================
   第 2 部分：数据清理 8 步流程 -> 生成干净表 (Clean Tables)
   ========================================================================= */

-- ---------------------------------------------------------------------------
-- 2.1 清理 companies （公司/工地维度表）
--   1) 移除无关数据：无
--   2) 消除重复：companies.csv 本身无重复行
--   3) 修复结构错误：修正城市/公司类型/工地类别的拼写错误
--   5) 处理缺失值：const_site_category 为空 -> 'N/A'（对 Administration / Development
--      Center 而言"无工地类别"本身是合理状态，不是数据缺失，用 'N/A' 显式标注）
--   6) 标准化：统一大小写、去除首尾空格、统一州名写法
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS companies_clean;
CREATE TABLE companies_clean (
    company_id      INT AUTO_INCREMENT PRIMARY KEY,
    company_name    VARCHAR(100) NOT NULL UNIQUE,
    city            VARCHAR(50)  NOT NULL,
    state           VARCHAR(50)  NOT NULL,
    company_type    VARCHAR(50)  NOT NULL,
    site_category   VARCHAR(50)  NOT NULL
) ENGINE=InnoDB;

INSERT INTO companies_clean (company_name, city, state, company_type, site_category)
SELECT
    TRIM(company_name),
    CASE TRIM(company_city)
         WHEN 'Goianiaa' THEN 'Goiania'
         ELSE TRIM(company_city)
    END,
    CASE TRIM(company_state)
         WHEN 'GOIAS' THEN 'Goias'
         ELSE TRIM(company_state)
    END,
    CASE TRIM(company_type)
         WHEN 'Construction Site s' THEN 'Construction Site'
         WHEN 'Construction Sites'  THEN 'Construction Site'
         ELSE TRIM(company_type)
    END,
    CASE
         WHEN const_site_category IS NULL OR TRIM(const_site_category) = '' THEN 'N/A'
         WHEN TRIM(const_site_category) = 'Commerciall' THEN 'Commercial'
         ELSE TRIM(const_site_category)
    END
FROM stg_companies;

-- ---------------------------------------------------------------------------
-- 2.2 清理 employees （员工维度表）
--   1) 移除无关数据：丢弃不可靠的 comp_code_emp 字段（见 1.2 诊断结果）
--   4) 类型转换：employee_code_emp / age 转成 INT
--   5) 缺失值：本表经检查无缺失
--   6) 标准化：性别统一为大写 'M'/'F'，姓名去除首尾空格
--   8) 验证：employee_id 唯一
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS employees_clean;
CREATE TABLE employees_clean (
    employee_id    INT PRIMARY KEY,
    employee_name  VARCHAR(100) NOT NULL,
    gender         CHAR(1) NOT NULL,
    age            TINYINT NOT NULL
) ENGINE=InnoDB;

INSERT INTO employees_clean (employee_id, employee_name, gender, age)
SELECT
    CAST(employee_code_emp AS UNSIGNED),
    TRIM(employee_name_emp),
    UPPER(TRIM(gender_raw)),
    CAST(age AS UNSIGNED)
FROM stg_employees;

-- ---------------------------------------------------------------------------
-- 2.3 清理 functions （职位/职能组维度表）
--   经检查该表本身无重复、无缺失、无格式问题，只做标准字段类型转换与去空格
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS functions_clean;
CREATE TABLE functions_clean (
    function_code    INT PRIMARY KEY,
    function_name    VARCHAR(100) NOT NULL,
    function_group   VARCHAR(50)  NOT NULL
) ENGINE=InnoDB;

INSERT INTO functions_clean (function_code, function_name, function_group)
SELECT
    CAST(function_code AS UNSIGNED),
    TRIM(function_name),
    TRIM(function_group)
FROM stg_functions;

-- ---------------------------------------------------------------------------
-- 2.4 清理 salaries （工资事实表，核心清理对象）
--   1) 移除无关数据：不再保留冗余的 comp_code（不可靠，见 1.3），
--      改用公司名称 company_name 作为关联键；同时不再保留冗余的
--      func_name/comp_name 文本（改由外键 JOIN 维度表取得）
--   2) 消除重复：DISTINCT 去除 186 行完全重复记录
--   3) 修复结构错误：日期统一解析为 DATE 类型（原格式 dd/mm/yyyy hh:mm，
--      且 日 恒为 01，代表"发薪当月"）
--   4) 类型转换：salary 字段用逗号做小数点 -> 替换为句点后转 DECIMAL(12,2)；
--      employee_id / func_code 转 INT
--   5) 缺失值处理：70 行工资为空 -> 保留记录但 salary_amount 记为 NULL，
--      分析时 AVG/SUM 等聚合函数会自动跳过 NULL，不会造成偏差，
--      同时不删除整行，保留员工-月份-职位的完整履历
--   7) 异常值处理：6 条 1,000,000 的工资（远超其余工资 3 个数量级，
--      且同一批次、同一工地、同一天集中出现，判定为录入错误）
--      标记 is_outlier=1，并将 salary_amount 置为 NULL，不纳入平均值/求和，
--      但原始错误值保留在 salary_raw 字段，便于审计还原
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS salaries_clean;
CREATE TABLE salaries_clean (
    salary_id       INT AUTO_INCREMENT PRIMARY KEY,
    company_name    VARCHAR(100) NOT NULL,
    employee_id     INT NOT NULL,
    pay_month       DATE NOT NULL,
    func_code       INT NOT NULL,
    salary_raw      DECIMAL(12,2) NULL,   -- 原始清洗后数值（含异常值，仅审计用）
    is_outlier      TINYINT(1) NOT NULL DEFAULT 0,
    salary_amount   DECIMAL(12,2) NULL    -- 分析用字段：缺失值/异常值均为 NULL
) ENGINE=InnoDB;

INSERT INTO salaries_clean (company_name, employee_id, pay_month, func_code, salary_raw, is_outlier, salary_amount)
SELECT
    TRIM(comp_name)                                            AS company_name,
    CAST(employee_id AS UNSIGNED)                               AS employee_id,
    STR_TO_DATE(SUBSTRING_INDEX(pay_date_raw,' ',1), '%d/%m/%Y') AS pay_month,
    CAST(func_code AS UNSIGNED)                                 AS func_code,
    v.salary_num                                                AS salary_raw,
    CASE WHEN v.salary_num > 100000 THEN 1 ELSE 0 END           AS is_outlier,
    CASE WHEN v.salary_num > 100000 THEN NULL ELSE v.salary_num END AS salary_amount
FROM (
    -- 先按全部字段去重，解决"重复行"问题
    SELECT DISTINCT comp_code, comp_name, employee_id, employee_name,
           pay_date_raw, func_code, func_name, salary_raw
    FROM stg_salaries
) d
CROSS JOIN LATERAL (
    SELECT CASE WHEN d.salary_raw IS NULL OR TRIM(d.salary_raw) = '' THEN NULL
                ELSE CAST(REPLACE(d.salary_raw, ',', '.') AS DECIMAL(12,2))
           END AS salary_num
) v;

-- 补充外键约束（在数据已清理、可以保证引用完整性之后再加，避免导入过程报错中断）
ALTER TABLE salaries_clean
  ADD CONSTRAINT fk_sal_company  FOREIGN KEY (company_name) REFERENCES companies_clean(company_name),
  ADD CONSTRAINT fk_sal_employee FOREIGN KEY (employee_id)  REFERENCES employees_clean(employee_id),
  ADD CONSTRAINT fk_sal_function FOREIGN KEY (func_code)    REFERENCES functions_clean(function_code);


/* ============================================================================
   第 3 部分：数据整合 (Integrate) -> 生成分析用宽表 / 视图 payroll_fact
   将四张干净表按业务主键关联，形成一张"人力资源工资分析宽表"，
   后续所有分析查询都基于这张视图，避免重复写 JOIN。
   ========================================================================= */
DROP VIEW IF EXISTS payroll_fact;
CREATE VIEW payroll_fact AS
SELECT
    s.salary_id,
    s.pay_month,
    YEAR(s.pay_month)  AS pay_year,
    MONTH(s.pay_month) AS pay_month_num,
    e.employee_id,
    e.employee_name,
    e.gender,
    e.age,
    c.company_name,
    c.city,
    c.state,
    c.company_type,
    c.site_category,
    f.function_code,
    f.function_name,
    f.function_group,
    s.salary_amount,
    s.is_outlier
FROM salaries_clean s
JOIN employees_clean e ON s.employee_id  = e.employee_id
JOIN companies_clean c ON s.company_name = c.company_name
JOIN functions_clean f ON s.func_code    = f.function_code;


/* ============================================================================
   第 4 部分：数据验证 (Validate)
   ========================================================================= */

-- 4.1 行数核对：清理前后应能解释差异（原始 8049 行 - 186 行重复 = 7863 行）
SELECT
  (SELECT COUNT(*) FROM stg_salaries)   AS raw_rows,
  (SELECT COUNT(*) FROM salaries_clean) AS clean_rows,
  (SELECT COUNT(*) FROM stg_salaries) - (SELECT COUNT(*) FROM salaries_clean) AS removed_duplicates;

-- 4.2 引用完整性：payroll_fact 行数应等于 salaries_clean 行数（无孤儿记录）
SELECT
  (SELECT COUNT(*) FROM salaries_clean) AS salaries_clean_rows,
  (SELECT COUNT(*) FROM payroll_fact)   AS payroll_fact_rows;

-- 4.3 取值域检查：性别、州、公司类型是否已标准化为预期的有限取值集合
SELECT DISTINCT gender FROM employees_clean;                 -- 期望仅 'M','F'
SELECT DISTINCT state  FROM companies_clean;                 -- 期望仅 3 个规范州名
SELECT DISTINCT company_type FROM companies_clean;           -- 期望无拼写变体

-- 4.4 工资范围检查：非空工资应全部为正数，且无超大异常值残留
SELECT MIN(salary_amount), MAX(salary_amount), AVG(salary_amount)
FROM salaries_clean
WHERE salary_amount IS NOT NULL;

-- 4.5 缺失值 / 异常值统计，作为报告中的数据质量总结
SELECT
  SUM(CASE WHEN salary_raw IS NULL AND is_outlier = 0 THEN 1 ELSE 0 END) AS missing_salary_rows,
  SUM(CASE WHEN is_outlier = 1 THEN 1 ELSE 0 END)                        AS outlier_rows,
  COUNT(*)                                                                AS total_rows
FROM salaries_clean;


/* ============================================================================
   第 5 部分：分析查询 —— 回答项目要求的 4 个业务问题
   ========================================================================= */

-- ---------------------------------------------------------------------------
-- 问题 1：工资是如何随时间变化的？（按发薪月份统计）
-- ---------------------------------------------------------------------------
SELECT
    pay_month,
    COUNT(*)                       AS employee_payments,
    ROUND(AVG(salary_amount), 2)   AS avg_salary,
    ROUND(SUM(salary_amount), 2)   AS total_payroll
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY pay_month
ORDER BY pay_month;

-- ---------------------------------------------------------------------------
-- 问题 2：哪个职能组 (function_group) 平均薪资最高 / 最低？
-- ---------------------------------------------------------------------------
SELECT
    function_group,
    COUNT(*)                        AS num_payments,
    COUNT(DISTINCT employee_id)     AS num_employees,
    ROUND(AVG(salary_amount), 2)    AS avg_salary,
    ROUND(MIN(salary_amount), 2)    AS min_salary,
    ROUND(MAX(salary_amount), 2)    AS max_salary
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY function_group
ORDER BY avg_salary DESC;
-- 结果第一行 = 平均薪资最高的职能组；最后一行 = 平均薪资最低的职能组

-- ---------------------------------------------------------------------------
-- 问题 3a：哪个公司性别薪酬差距最大？（按公司统计男女平均工资差）
-- ---------------------------------------------------------------------------
SELECT
    company_name,
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

-- 问题 3b：哪个职能组性别薪酬差距最大？
SELECT
    function_group,
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

-- ---------------------------------------------------------------------------
-- 问题 4：各州 (state) 薪资分布情况如何？
-- ---------------------------------------------------------------------------
SELECT
    state,
    COUNT(*)                          AS num_payments,
    COUNT(DISTINCT employee_id)       AS num_employees,
    ROUND(AVG(salary_amount), 2)      AS avg_salary,
    ROUND(MIN(salary_amount), 2)      AS min_salary,
    ROUND(MAX(salary_amount), 2)      AS max_salary,
    ROUND(SUM(salary_amount), 2)      AS total_payroll
FROM payroll_fact
WHERE salary_amount IS NOT NULL
GROUP BY state
ORDER BY avg_salary DESC;


/* ============================================================================
   第 6 部分：结果导出说明
   ========================================================================= */
-- 在 DBeaver 中执行以上第 5 部分的每条查询后：
--   右键 Export resultset... -> 选择 CSV -> 设置输出路径 -> Proceed -> 输出以下5个csv文件 
--     q1_salary_trend_over_time.csv
--     q2_avg_salary_by_function_group.csv
--     q3a_gender_pay_gap_by_company.csv
--     q3b_gender_pay_gap_by_function_group.csv
--     q4_salary_distribution_by_state.csv
-- ============================================================================