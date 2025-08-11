-- Comprehensive Cost Reporting Views
-- Provides business intelligence views for job order cost analysis
-- Excludes CANCELLED employees and job orders from cost calculations
-- Includes year splitting and funding source analysis

-- ============================================================================
-- CORE EMPLOYEE ASSIGNMENT VIEWS
-- ============================================================================

-- Job Order Employee Period View
-- Shows each employee assignment with period details and working days
CREATE OR REPLACE VIEW v_job_order_employee_period AS
SELECT 
    jo.job_order_id,
    jo.jo_number,
    jo.jo_date,
    jo.start_date,
    jo.end_date,
    e.employee_id,
    e.full_name as employee_name,
    d.designation_name,
    joa.daily_rate,
    joa.duration_hours,
    oa.office_name as office_assignment,
    o.office_name as main_office,
    working_days(jo.start_date, jo.end_date) as total_working_days,
    jo.status as job_order_status,
    e.status as employee_status,
    joa.status as assignment_status,
    joa.conforme,
    joa.created_at as assignment_created,
    joa.updated_at as assignment_updated
FROM job_orders jo
JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
JOIN employees e ON joa.employee_id = e.employee_id
LEFT JOIN designations d ON joa.designation_id = d.designation_id
LEFT JOIN offices oa ON joa.office_assignment_id = oa.office_id
LEFT JOIN offices o ON jo.office_id = o.office_id
-- Exclude CANCELLED records as per requirements
WHERE jo.status != 'CANCELLED' 
  AND e.status != 'CANCELLED' 
  AND joa.status != 'CANCELLED';

-- ============================================================================
-- COST CALCULATION VIEWS
-- ============================================================================

-- Job Order Employee Cost View
-- Calculates total estimated cost for each assignment
CREATE OR REPLACE VIEW v_job_order_employee_cost AS
SELECT 
    p.*,
    p.total_working_days * p.daily_rate as estimated_cost
FROM v_job_order_employee_period p;

-- Job Order Employee Cost by Year View
-- Splits costs across fiscal years for cross-year assignments
CREATE OR REPLACE VIEW v_job_order_employee_cost_by_year AS
SELECT 
    p.job_order_id,
    p.jo_number,
    p.employee_id,
    p.employee_name,
    p.designation_name,
    p.daily_rate,
    p.office_assignment,
    p.main_office,
    wd.fiscal_year,
    wd.working_days_count,
    wd.working_days_count * p.daily_rate as year_cost,
    p.job_order_status,
    p.employee_status,
    p.assignment_status
FROM v_job_order_employee_period p
CROSS JOIN LATERAL working_days_by_fiscal_year(p.start_date, p.end_date) wd
WHERE wd.working_days_count > 0;

-- ============================================================================
-- FUNDING SOURCE VIEWS
-- ============================================================================

-- Funding Source Balances View
-- Shows funding commitments and balances by source
CREATE OR REPLACE VIEW v_funding_source_balances AS
SELECT 
    fs.funding_source_id,
    fs.funding_code,
    fs.funding_description,
    fsa.fiscal_year,
    COUNT(DISTINCT fsa.job_order_id) as active_job_orders,
    COUNT(DISTINCT joa.employee_id) as assigned_employees,
    SUM(
        CASE 
            WHEN fsa.allocation_percentage > 0 THEN
                working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                joa.daily_rate * 
                (fsa.allocation_percentage / 100.0)
            ELSE
                working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                joa.daily_rate
        END
    ) as total_commitment,
    SUM(
        CASE 
            WHEN jo.status = 'ACTIVE' THEN
                CASE 
                    WHEN fsa.allocation_percentage > 0 THEN
                        working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                        joa.daily_rate * 
                        (fsa.allocation_percentage / 100.0)
                    ELSE
                        working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                        joa.daily_rate
                END
            ELSE 0
        END
    ) as active_commitment,
    SUM(
        CASE 
            WHEN jo.status = 'RESERVED' THEN
                CASE 
                    WHEN fsa.allocation_percentage > 0 THEN
                        working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                        joa.daily_rate * 
                        (fsa.allocation_percentage / 100.0)
                    ELSE
                        working_days_in_fiscal_year(jo.start_date, jo.end_date, fsa.fiscal_year) * 
                        joa.daily_rate
                END
            ELSE 0
        END
    ) as reserved_commitment
FROM funding_sources fs
JOIN funding_source_allocations fsa ON fs.funding_source_id = fsa.funding_source_id
JOIN job_orders jo ON fsa.job_order_id = jo.job_order_id
JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
-- Include ACTIVE and RESERVED per Policy 2, exclude CANCELLED
WHERE jo.status IN ('ACTIVE', 'RESERVED')
  AND joa.status IN ('ACTIVE', 'RESERVED')
GROUP BY fs.funding_source_id, fs.funding_code, fs.funding_description, fsa.fiscal_year;

-- ============================================================================
-- MONTHLY REPORTING VIEWS
-- ============================================================================

-- Monthly Employees per Funding Source View
CREATE OR REPLACE VIEW v_monthly_employees_per_funding AS
SELECT 
    fs.funding_code,
    fs.funding_description,
    DATE_TRUNC('month', generate_series) as month_year,
    COUNT(DISTINCT joa.employee_id) as employee_count,
    SUM(joa.daily_rate) as total_daily_rates,
    AVG(joa.daily_rate) as average_daily_rate
FROM funding_sources fs
JOIN funding_source_allocations fsa ON fs.funding_source_id = fsa.funding_source_id
JOIN job_orders jo ON fsa.job_order_id = jo.job_order_id
JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
CROSS JOIN generate_series(
    DATE_TRUNC('month', jo.start_date),
    DATE_TRUNC('month', jo.end_date),
    '1 month'::interval
) generate_series
-- Exclude CANCELLED records
WHERE jo.status != 'CANCELLED' 
  AND joa.status != 'CANCELLED'
GROUP BY fs.funding_code, fs.funding_description, DATE_TRUNC('month', generate_series)
ORDER BY fs.funding_code, month_year;

-- ============================================================================
-- EMPLOYEE SERVICE RECORD VIEW
-- ============================================================================

-- Employee Service Record View
-- Comprehensive service history for each employee
CREATE OR REPLACE VIEW v_employee_service_record AS
SELECT 
    e.employee_id,
    e.full_name as employee_name,
    e.status as employee_status,
    COUNT(DISTINCT jo.job_order_id) as total_assignments,
    MIN(jo.start_date) as first_assignment_date,
    MAX(jo.end_date) as last_assignment_date,
    SUM(working_days(jo.start_date, jo.end_date)) as total_working_days,
    COUNT(DISTINCT d.designation_id) as different_designations,
    STRING_AGG(DISTINCT d.designation_name, ', ' ORDER BY d.designation_name) as designations_held,
    COUNT(DISTINCT oa.office_id) as offices_worked,
    STRING_AGG(DISTINCT oa.office_name, ', ' ORDER BY oa.office_name) as offices_list,
    COUNT(DISTINCT fs.funding_source_id) as funding_sources_count,
    AVG(joa.daily_rate) as average_daily_rate,
    MIN(joa.daily_rate) as min_daily_rate,
    MAX(joa.daily_rate) as max_daily_rate,
    SUM(working_days(jo.start_date, jo.end_date) * joa.daily_rate) as total_estimated_earnings,
    COUNT(*) FILTER (WHERE jo.status = 'ACTIVE') as active_assignments,
    COUNT(*) FILTER (WHERE jo.status = 'RESERVED') as reserved_assignments,
    COUNT(*) FILTER (WHERE jo.status = 'CANCELLED') as cancelled_assignments
FROM employees e
LEFT JOIN job_order_assignments joa ON e.employee_id = joa.employee_id
LEFT JOIN job_orders jo ON joa.job_order_id = jo.job_order_id
LEFT JOIN designations d ON joa.designation_id = d.designation_id
LEFT JOIN offices oa ON joa.office_assignment_id = oa.office_id
LEFT JOIN funding_source_allocations fsa ON jo.job_order_id = fsa.job_order_id
LEFT JOIN funding_sources fs ON fsa.funding_source_id = fs.funding_source_id
GROUP BY e.employee_id, e.full_name, e.status;

-- ============================================================================
-- PRINTABLE REPORT VIEWS
-- ============================================================================

-- Printable Job Order Header View
-- Summary information for job order headers
CREATE OR REPLACE VIEW v_printable_job_order_header AS
SELECT 
    jo.jo_number,
    jo.jo_date,
    jo.start_date,
    jo.end_date,
    working_days(jo.start_date, jo.end_date) as total_working_days,
    o.office_name as issuing_office,
    jo.status,
    COUNT(joa.employee_id) as total_employees,
    SUM(joa.daily_rate) as total_daily_rates,
    SUM(working_days(jo.start_date, jo.end_date) * joa.daily_rate) as total_estimated_cost,
    STRING_AGG(DISTINCT fs.funding_code, '; ' ORDER BY fs.funding_code) as funding_sources,
    STRING_AGG(DISTINCT d.designation_name, '; ' ORDER BY d.designation_name) as designations_involved
FROM job_orders jo
LEFT JOIN offices o ON jo.office_id = o.office_id
LEFT JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
LEFT JOIN designations d ON joa.designation_id = d.designation_id
LEFT JOIN funding_source_allocations fsa ON jo.job_order_id = fsa.job_order_id
LEFT JOIN funding_sources fs ON fsa.funding_source_id = fs.funding_source_id
-- Include all statuses for comprehensive reporting
GROUP BY jo.job_order_id, jo.jo_number, jo.jo_date, jo.start_date, jo.end_date, o.office_name, jo.status;

-- Printable Job Order Roster View
-- Detailed employee roster for each job order
CREATE OR REPLACE VIEW v_printable_job_order_roster AS
SELECT 
    jo.jo_number,
    jo.jo_date,
    jo.start_date,
    jo.end_date,
    e.full_name as employee_name,
    d.designation_name,
    joa.daily_rate,
    joa.duration_hours,
    oa.office_name as office_assignment,
    working_days(jo.start_date, jo.end_date) as working_days,
    working_days(jo.start_date, jo.end_date) * joa.daily_rate as estimated_cost,
    joa.conforme,
    jo.status as job_order_status,
    e.status as employee_status,
    joa.status as assignment_status,
    STRING_AGG(fs.funding_code, '; ') as funding_sources,
    ROW_NUMBER() OVER (PARTITION BY jo.jo_number ORDER BY e.full_name) as roster_sequence
FROM job_orders jo
JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
JOIN employees e ON joa.employee_id = e.employee_id
LEFT JOIN designations d ON joa.designation_id = d.designation_id
LEFT JOIN offices oa ON joa.office_assignment_id = oa.office_id
LEFT JOIN funding_source_allocations fsa ON jo.job_order_id = fsa.job_order_id
LEFT JOIN funding_sources fs ON fsa.funding_source_id = fs.funding_source_id
GROUP BY 
    jo.job_order_id, jo.jo_number, jo.jo_date, jo.start_date, jo.end_date,
    e.employee_id, e.full_name, e.status,
    d.designation_name, joa.daily_rate, joa.duration_hours, joa.conforme,
    oa.office_name, jo.status, joa.status
ORDER BY jo.jo_number, e.full_name;

-- ============================================================================
-- PERFORMANCE INDEXES FOR VIEWS
-- ============================================================================

-- Additional indexes to optimize view performance
-- (Most should already exist from schema.sql)

-- Composite indexes for frequent view queries
CREATE INDEX IF NOT EXISTS idx_job_order_assignments_composite 
ON job_order_assignments(job_order_id, employee_id, status);

CREATE INDEX IF NOT EXISTS idx_funding_allocations_composite 
ON funding_source_allocations(job_order_id, funding_source_id, fiscal_year);

-- ============================================================================
-- VIEW DOCUMENTATION
-- ============================================================================

COMMENT ON VIEW v_job_order_employee_period IS 'Shows employee assignments with period details and working days calculation';
COMMENT ON VIEW v_job_order_employee_cost IS 'Calculates total estimated cost (working_days * daily_rate) for each assignment';
COMMENT ON VIEW v_job_order_employee_cost_by_year IS 'Splits assignment costs across fiscal years for cross-year periods';
COMMENT ON VIEW v_funding_source_balances IS 'Shows funding source commitments and balances excluding CANCELLED records';
COMMENT ON VIEW v_monthly_employees_per_funding IS 'Monthly headcount and cost summary by funding source';
COMMENT ON VIEW v_employee_service_record IS 'Comprehensive service history and statistics for each employee';
COMMENT ON VIEW v_printable_job_order_header IS 'Summary information suitable for job order header reports';
COMMENT ON VIEW v_printable_job_order_roster IS 'Detailed employee roster for job order printing';

/*
Example Queries:
================

-- 1. Get cost breakdown for a specific job order
SELECT * FROM v_job_order_employee_cost 
WHERE jo_number = 'AB2024-12-001'
ORDER BY employee_name;

-- 2. See how costs split across fiscal years
SELECT 
    jo_number, 
    employee_name, 
    fiscal_year, 
    working_days_count, 
    year_cost 
FROM v_job_order_employee_cost_by_year 
WHERE jo_number LIKE 'AB2024%'
ORDER BY jo_number, employee_name, fiscal_year;

-- 3. Check funding source balances for current fiscal year
SELECT * FROM v_funding_source_balances 
WHERE fiscal_year = 2024
ORDER BY total_commitment DESC;

-- 4. Monthly employee counts by funding source
SELECT 
    funding_code,
    month_year,
    employee_count,
    total_daily_rates
FROM v_monthly_employees_per_funding 
WHERE month_year >= '2024-01-01'
ORDER BY funding_code, month_year;

-- 5. Employee service record summary
SELECT 
    employee_name,
    total_assignments,
    total_working_days,
    total_estimated_earnings,
    average_daily_rate,
    designations_held
FROM v_employee_service_record
WHERE employee_status = 'ACTIVE'
ORDER BY total_estimated_earnings DESC;

-- 6. Printable job order report
SELECT * FROM v_printable_job_order_header 
WHERE jo_number = 'AB2024-12-001';

SELECT * FROM v_printable_job_order_roster 
WHERE jo_number = 'AB2024-12-001'
ORDER BY roster_sequence;

-- 7. Find employees working across multiple funding sources
SELECT 
    employee_name,
    funding_sources_count,
    offices_worked,
    total_assignments
FROM v_employee_service_record
WHERE funding_sources_count > 1
ORDER BY funding_sources_count DESC;

-- 8. Cost analysis excluding CANCELLED records (automatic in views)
SELECT 
    SUM(estimated_cost) as total_active_cost,
    COUNT(DISTINCT employee_id) as active_employees,
    COUNT(DISTINCT jo_number) as active_job_orders
FROM v_job_order_employee_cost;
*/