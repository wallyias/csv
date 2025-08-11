# PostgreSQL Normalization Pipeline for Job Order Management

This repository provides a comprehensive PostgreSQL normalization pipeline for job order data management with advanced cost calculation, working day computation, and funding source tracking capabilities.

## 📋 Overview

The system transforms raw CSV job order data into a normalized PostgreSQL database with:

- **Normalized schema** with proper relationships and constraints
- **Working day calculations** (Monday-Friday, excluding holidays)
- **Cost computation** with fiscal year splitting
- **Funding source allocation** tracking and balance management
- **Status-based filtering** (ACTIVE/RESERVED/CANCELLED with exclusions)
- **Comprehensive reporting views** for analysis and printable reports

## 🏗️ Architecture

### Core Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   stagingjo.csv │───▶│  Staging Tables  │───▶│ Normalized DB   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │                         │
                              ▼                         ▼
                       ┌──────────────┐         ┌──────────────┐
                       │ Data Cleaning│         │ Reporting    │
                       │ (etl/clean.py)│         │ Views        │
                       └──────────────┘         └──────────────┘
```

### Database Schema

**Core Tables:**
- `employees` - Employee master data
- `job_orders` - Job order header information
- `job_order_assignments` - Employee-to-job-order assignments
- `offices` - Office/department lookup
- `designations` - Job designation lookup
- `funding_sources` - Funding source master
- `funding_source_allocations` - Funding allocations with year splitting
- `holidays` - Holiday calendar for working day calculations

## 🚀 Quick Start

### 1. Database Setup

```sql
-- Create database
CREATE DATABASE job_orders;
\c job_orders;

-- Run schema creation
\i schema.sql

-- Create staging table
\i staging.sql
```

### 2. Data Import and Cleaning

```bash
# Clean the CSV data (optional but recommended)
python etl/clean.py stagingjo.csv stagingjo_cleaned.csv

# Import into staging table
psql job_orders -c "\COPY staging_csv(jo_number, jo_date, employee_name, designation, daily_rate, start_jo, end_jo, office_assignment, duration, conforme, fund_charges, office) FROM 'stagingjo_cleaned.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '\"', ESCAPE '\"');"
```

### 3. Data Transformation

```sql
-- Add encoding fix functions
\i sql/functions_fix_encoding.sql

-- Apply encoding fixes to staging data
CALL fix_staging_encoding();

-- Transform staging data to normalized tables
\i transform.sql

-- Add advanced working day functions
\i sql/working_day_functions.sql

-- Create reporting views
\i sql/views_cost_reporting.sql
```

### 4. Holiday Setup (Important!)

```sql
-- Add holidays for accurate working day calculations
INSERT INTO holidays (holiday_date, holiday_name, holiday_type) VALUES 
('2024-01-01', 'New Year''s Day', 'PUBLIC'),
('2024-04-09', 'Araw ng Kagitingan', 'PUBLIC'),
('2024-05-01', 'Labor Day', 'PUBLIC'),
('2024-06-12', 'Independence Day', 'PUBLIC'),
('2024-08-26', 'National Heroes Day', 'PUBLIC'),
('2024-11-30', 'Bonifacio Day', 'PUBLIC'),
('2024-12-25', 'Christmas Day', 'PUBLIC'),
('2024-12-30', 'Rizal Day', 'PUBLIC'),
('2025-01-01', 'New Year''s Day', 'PUBLIC');
```

## 📊 Key Features

### Cost Calculation Formula

```
estimated_cost = working_days × daily_rate
```

Where `working_days` = weekdays (Mon-Fri) excluding holidays

### Status Policy Implementation

The system implements **Policy 2 (RESERVED + ACTIVE commit)**:

- **ACTIVE**: Currently active assignments (included in all calculations)
- **RESERVED**: Reserved assignments (included in funding balance calculations)
- **CANCELLED**: Cancelled assignments (excluded from cost calculations and funding balances)

### Fiscal Year Splitting

For job orders spanning multiple fiscal years, costs are automatically split based on working days in each year:

```sql
-- Example: Job order from Dec 2024 to Feb 2025
SELECT * FROM v_job_order_employee_cost_by_year 
WHERE jo_number = 'AB2024-12-001';
```

## 📈 Key Reporting Views

### 1. Employee Cost Analysis

```sql
-- Total cost by employee
SELECT 
    employee_name,
    SUM(estimated_cost) as total_cost,
    COUNT(*) as assignments
FROM v_job_order_employee_cost
GROUP BY employee_name
ORDER BY total_cost DESC;
```

### 2. Funding Source Balances

```sql
-- Current funding commitments
SELECT * FROM v_funding_source_balances 
WHERE fiscal_year = 2024
ORDER BY total_commitment DESC;
```

### 3. Monthly Employee Counts

```sql
-- Monthly headcount by funding source
SELECT * FROM v_monthly_employees_per_funding
WHERE month_year >= '2024-01-01'
ORDER BY funding_code, month_year;
```

### 4. Service Records

```sql
-- Employee service history
SELECT * FROM v_employee_service_record
WHERE employee_status = 'ACTIVE'
ORDER BY total_estimated_earnings DESC;
```

## 🔧 Data Management

### Updating Status

```sql
-- Mark employees as CANCELLED (excludes from cost calculations)
UPDATE employees SET status = 'CANCELLED' 
WHERE full_name LIKE '%John Doe%';

-- Mark job orders as RESERVED
UPDATE job_orders SET status = 'RESERVED' 
WHERE jo_number LIKE 'AB2024-12-%';

-- Mark specific assignments as CANCELLED
UPDATE job_order_assignments SET status = 'CANCELLED' 
WHERE assignment_id = 123;
```

### Managing Funding Allocations

```sql
-- Update allocation percentages for split funding
UPDATE funding_source_allocations 
SET allocation_percentage = 50.0
WHERE job_order_id = 1 AND funding_source_id = 1;

-- Add additional funding source for a job order
INSERT INTO funding_source_allocations (job_order_id, funding_source_id, allocation_percentage, fiscal_year)
VALUES (1, 2, 50.0, 2024);
```

### Holiday Management

```sql
-- Add new holiday
INSERT INTO holidays (holiday_date, holiday_name, holiday_type) 
VALUES ('2024-08-21', 'Ninoy Aquino Day', 'SPECIAL');

-- Deactivate a holiday
UPDATE holidays SET is_active = FALSE 
WHERE holiday_date = '2024-08-21';
```

## 📋 Available Views Summary

| View Name | Purpose |
|-----------|---------|
| `v_job_order_employee_period` | Employee assignments with period details |
| `v_job_order_employee_cost` | Cost calculations per assignment |
| `v_job_order_employee_cost_by_year` | Fiscal year cost splitting |
| `v_funding_source_balances` | Funding commitments and balances |
| `v_monthly_employees_per_funding` | Monthly headcount analysis |
| `v_employee_service_record` | Comprehensive employee history |
| `v_printable_job_order_header` | Job order summary reports |
| `v_printable_job_order_roster` | Detailed employee rosters |

## 🔍 Data Quality Checks

### Validation Queries

```sql
-- Check for missing critical data
SELECT 'Missing job order data' as issue, COUNT(*) as count
FROM staging_csv WHERE jo_number IS NULL OR employee_name IS NULL
UNION ALL
SELECT 'Zero or negative rates', COUNT(*)
FROM job_order_assignments WHERE daily_rate <= 0
UNION ALL
SELECT 'Invalid date ranges', COUNT(*)
FROM job_orders WHERE start_date > end_date;

-- Check transformation completeness
SELECT 
    'Staging Records' as table_name, COUNT(*) as count FROM staging_csv
UNION ALL
SELECT 'Job Orders', COUNT(*) FROM job_orders
UNION ALL
SELECT 'Employees', COUNT(*) FROM employees
UNION ALL
SELECT 'Assignments', COUNT(*) FROM job_order_assignments;

-- Find encoding issues
SELECT staging_id, employee_name 
FROM staging_csv 
WHERE detect_encoding_issues(employee_name);
```

## 🛠️ Maintenance Tasks

### Regular Maintenance

1. **Update holiday calendar** annually
2. **Review and update employee statuses** as needed
3. **Adjust funding allocations** for complex splits
4. **Monitor data quality** with validation queries
5. **Archive old data** based on retention policies

### Performance Optimization

```sql
-- Refresh statistics
ANALYZE;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_tup_read, idx_tup_fetch 
FROM pg_stat_user_indexes 
WHERE idx_tup_read > 0;
```

## 🚨 Troubleshooting

### Common Issues

1. **CSV Import Errors**
   - Run `python etl/clean.py` to fix encoding and format issues
   - Check for extra commas in quoted fields

2. **Zero Working Days**
   - Verify holiday table is populated
   - Check date ranges are valid (start_date <= end_date)

3. **Missing Cost Calculations**
   - Ensure employees/job orders are not CANCELLED
   - Verify funding_source_allocations table is populated

4. **Encoding Issues**
   - Run encoding fix procedures: `CALL fix_staging_encoding();`
   - Check character encoding of source CSV file

### Performance Issues

```sql
-- Find slow queries
SELECT query, mean_time, calls 
FROM pg_stat_statements 
WHERE mean_time > 1000 
ORDER BY mean_time DESC;

-- Check table sizes
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## 📝 File Structure

```
├── schema.sql                      # Core database schema
├── staging.sql                     # Staging table structure
├── transform.sql                   # ETL transformation logic
├── etl/
│   └── clean.py                   # CSV data cleaning script
├── sql/
│   ├── functions_fix_encoding.sql # Encoding fix functions
│   ├── working_day_functions.sql  # Working day calculations
│   └── views_cost_reporting.sql   # Comprehensive reporting views
└── README.md                      # This documentation
```

## 🔐 Security Notes

- Use proper PostgreSQL user permissions
- Regularly backup the database
- Monitor access to sensitive salary/rate information
- Consider row-level security for multi-tenant scenarios

## 📚 Additional Resources

- PostgreSQL Documentation: https://www.postgresql.org/docs/
- CSV Import Best Practices
- Working Day Calculation Methods
- Fiscal Year Management Strategies

---

**Note**: This system implements Policy 2 with ACTIVE and RESERVED commitments. All imported job orders are initially set to ACTIVE status and can be manually adjusted as needed. CANCELLED employees and job orders are automatically excluded from cost calculations and funding balance views.