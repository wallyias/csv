-- ETL Transformation Script
-- Transforms data from staging_csv into normalized tables
-- Excludes CANCELLED employees and job orders from cost calculations
-- References new funding_source_allocations table

-- ============================================================================
-- UTILITY FUNCTIONS FOR DATA TRANSFORMATION
-- ============================================================================

-- Function to parse date strings into proper dates
CREATE OR REPLACE FUNCTION parse_date_string(date_str TEXT)
RETURNS DATE AS $$
BEGIN
    -- Handle various date formats from CSV
    -- Example formats: "December 27, 2024", "January 01, 2025"
    
    -- First try standard format
    BEGIN
        RETURN date_str::DATE;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -- Try to parse month name format
    BEGIN
        RETURN TO_DATE(date_str, 'Month DD, YYYY');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -- Return null if unable to parse
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to clean and convert rate strings to decimal
CREATE OR REPLACE FUNCTION parse_rate_string(rate_str TEXT)
RETURNS DECIMAL(10,2) AS $$
BEGIN
    -- Remove any currency symbols and convert to decimal
    -- Handle cases like "407.27" or "$407.27"
    BEGIN
        RETURN REGEXP_REPLACE(rate_str, '[^0-9.]', '', 'g')::DECIMAL(10,2);
    EXCEPTION WHEN OTHERS THEN
        RETURN 0.00;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 1: POPULATE LOOKUP TABLES
-- ============================================================================

-- Insert unique offices
INSERT INTO offices (office_code, office_name)
SELECT DISTINCT 
    COALESCE(office, 'UNKNOWN') as office_code,
    COALESCE(office, 'UNKNOWN') as office_name
FROM staging_csv 
WHERE office IS NOT NULL
ON CONFLICT (office_code) DO NOTHING;

-- Insert unique office assignments (might be different from main office)
INSERT INTO offices (office_code, office_name)
SELECT DISTINCT 
    COALESCE(office_assignment, 'UNKNOWN') as office_code,
    COALESCE(office_assignment, 'UNKNOWN') as office_name
FROM staging_csv 
WHERE office_assignment IS NOT NULL 
    AND office_assignment NOT IN (SELECT office_code FROM offices)
ON CONFLICT (office_code) DO NOTHING;

-- Insert unique designations
INSERT INTO designations (designation_name)
SELECT DISTINCT designation
FROM staging_csv 
WHERE designation IS NOT NULL
ON CONFLICT (designation_name) DO NOTHING;

-- Insert unique funding sources
INSERT INTO funding_sources (funding_code, funding_description)
SELECT DISTINCT 
    SUBSTRING(fund_charges, 1, 100) as funding_code,
    fund_charges as funding_description
FROM staging_csv 
WHERE fund_charges IS NOT NULL
ON CONFLICT (funding_code) DO NOTHING;

-- ============================================================================
-- STEP 2: POPULATE EMPLOYEES TABLE
-- ============================================================================

-- Insert unique employees (all imported as ACTIVE per requirements)
INSERT INTO employees (full_name, status)
SELECT DISTINCT 
    employee_name,
    'ACTIVE'::status_type  -- Currently all imported JOs set to ACTIVE per requirements
FROM staging_csv 
WHERE employee_name IS NOT NULL
ON CONFLICT DO NOTHING;

-- ============================================================================
-- STEP 3: POPULATE JOB ORDERS TABLE
-- ============================================================================

-- Insert unique job orders
INSERT INTO job_orders (jo_number, jo_date, start_date, end_date, office_id, status)
SELECT DISTINCT
    s.jo_number,
    parse_date_string(s.jo_date),
    parse_date_string(s.start_jo),
    parse_date_string(s.end_jo),
    o.office_id,
    'ACTIVE'::status_type  -- Currently all imported JOs set to ACTIVE per requirements
FROM staging_csv s
LEFT JOIN offices o ON o.office_code = s.office
WHERE s.jo_number IS NOT NULL
ON CONFLICT (jo_number) DO NOTHING;

-- ============================================================================
-- STEP 4: POPULATE JOB ORDER ASSIGNMENTS
-- ============================================================================

-- Insert job order assignments
INSERT INTO job_order_assignments (
    job_order_id, 
    employee_id, 
    designation_id, 
    daily_rate, 
    duration_hours, 
    office_assignment_id, 
    conforme,
    status
)
SELECT DISTINCT
    jo.job_order_id,
    e.employee_id,
    d.designation_id,
    parse_rate_string(s.daily_rate),
    s.duration,
    oa.office_id,
    NULLIF(s.conforme, ''),
    'ACTIVE'::status_type  -- Currently all imported assignments set to ACTIVE
FROM staging_csv s
JOIN job_orders jo ON jo.jo_number = s.jo_number
JOIN employees e ON e.full_name = s.employee_name
LEFT JOIN designations d ON d.designation_name = s.designation
LEFT JOIN offices oa ON oa.office_code = s.office_assignment
WHERE s.jo_number IS NOT NULL AND s.employee_name IS NOT NULL
ON CONFLICT (job_order_id, employee_id) DO NOTHING;

-- ============================================================================
-- STEP 5: POPULATE FUNDING SOURCE ALLOCATIONS
-- ============================================================================

-- Insert funding source allocations (100% allocation by default)
-- This creates the base allocations that can be adjusted later for year splitting
INSERT INTO funding_source_allocations (
    job_order_id,
    funding_source_id,
    allocation_percentage,
    fiscal_year
)
SELECT DISTINCT
    jo.job_order_id,
    fs.funding_source_id,
    100.00 as allocation_percentage,  -- Default 100% allocation
    EXTRACT(YEAR FROM jo.start_date) as fiscal_year
FROM staging_csv s
JOIN job_orders jo ON jo.jo_number = s.jo_number
JOIN funding_sources fs ON fs.funding_code = SUBSTRING(s.fund_charges, 1, 100)
WHERE s.fund_charges IS NOT NULL
ON CONFLICT (job_order_id, funding_source_id, fiscal_year) DO NOTHING;

-- Handle cross-year job orders by creating additional allocations for ending year
INSERT INTO funding_source_allocations (
    job_order_id,
    funding_source_id,
    allocation_percentage,
    fiscal_year
)
SELECT DISTINCT
    jo.job_order_id,
    fs.funding_source_id,
    0.00 as allocation_percentage,  -- Will be calculated by cost views based on working days
    EXTRACT(YEAR FROM jo.end_date) as fiscal_year
FROM staging_csv s
JOIN job_orders jo ON jo.jo_number = s.jo_number
JOIN funding_sources fs ON fs.funding_code = SUBSTRING(s.fund_charges, 1, 100)
WHERE s.fund_charges IS NOT NULL
    AND EXTRACT(YEAR FROM jo.start_date) != EXTRACT(YEAR FROM jo.end_date)
ON CONFLICT (job_order_id, funding_source_id, fiscal_year) DO NOTHING;

-- ============================================================================
-- STEP 6: UPDATE STAGING TABLE PROCESSING STATUS
-- ============================================================================

-- Mark records as processed
UPDATE staging_csv SET is_processed = TRUE;

-- ============================================================================
-- STEP 7: DATA VALIDATION AND CLEANUP
-- ============================================================================

-- Validation queries to check transformation results
/*
-- Check transformation results
SELECT 
    'Staging Records' as table_name, COUNT(*) as count FROM staging_csv
UNION ALL
SELECT 'Job Orders', COUNT(*) FROM job_orders
UNION ALL
SELECT 'Employees', COUNT(*) FROM employees
UNION ALL
SELECT 'Assignments', COUNT(*) FROM job_order_assignments
UNION ALL
SELECT 'Funding Allocations', COUNT(*) FROM funding_source_allocations
UNION ALL
SELECT 'Offices', COUNT(*) FROM offices
UNION ALL
SELECT 'Designations', COUNT(*) FROM designations
UNION ALL
SELECT 'Funding Sources', COUNT(*) FROM funding_sources;

-- Check for job orders spanning multiple years
SELECT 
    jo_number,
    start_date,
    end_date,
    EXTRACT(YEAR FROM start_date) as start_year,
    EXTRACT(YEAR FROM end_date) as end_year
FROM job_orders 
WHERE EXTRACT(YEAR FROM start_date) != EXTRACT(YEAR FROM end_date);

-- Check for any data quality issues
SELECT 
    'Invalid dates' as issue,
    COUNT(*) as count
FROM job_orders 
WHERE jo_date IS NULL OR start_date IS NULL OR end_date IS NULL
UNION ALL
SELECT 
    'Zero rates',
    COUNT(*)
FROM job_order_assignments 
WHERE daily_rate <= 0;
*/

-- ============================================================================
-- NOTES ON STATUS HANDLING AND CANCELLED RECORDS
-- ============================================================================

/*
Status Policy Notes:
===================

1. Current Import Policy: All records imported as ACTIVE
   - User specified Policy 2 (RESERVED + ACTIVE commit)
   - Currently all imported JOs set to ACTIVE per requirements

2. CANCELLED Status Exclusions:
   - CANCELLED employees are excluded from cost calculation views
   - CANCELLED job orders are excluded from funding balance calculations
   - Cost views in sql/views_cost_reporting.sql will filter out CANCELLED status

3. Manual Status Updates:
   - After import, update statuses as needed:
   
   -- Example: Mark specific employees as CANCELLED
   UPDATE employees SET status = 'CANCELLED' WHERE full_name LIKE '%specific_pattern%';
   
   -- Example: Mark specific job orders as RESERVED
   UPDATE job_orders SET status = 'RESERVED' WHERE jo_number LIKE 'AB2024-12-%';
   
   -- Example: Mark specific assignments as CANCELLED
   UPDATE job_order_assignments SET status = 'CANCELLED' 
   WHERE assignment_id IN (SELECT assignment_id FROM ...);

4. Funding Source Allocations:
   - Base allocations created at 100% for primary fiscal year
   - Cross-year allocations created at 0% (calculated dynamically in views)
   - Manual adjustment may be needed for complex funding splits

For detailed cost calculation views that respect these status exclusions,
see sql/views_cost_reporting.sql
*/

-- ETL transformation complete
-- Next steps: 
-- 1. Run sql/working_day_functions.sql for advanced working day calculations
-- 2. Run sql/views_cost_reporting.sql for comprehensive cost reporting views
-- 3. Populate holidays table for accurate working day calculations