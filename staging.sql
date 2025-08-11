-- Staging table for raw CSV import from stagingjo.csv
-- This table captures the raw data structure before normalization

-- Drop staging table if exists
DROP TABLE IF EXISTS staging_csv;

-- Create staging table matching CSV structure
CREATE TABLE staging_csv (
    staging_id SERIAL PRIMARY KEY,
    jo_number VARCHAR(50),
    jo_date VARCHAR(50),
    employee_name VARCHAR(255),
    designation VARCHAR(255),
    daily_rate VARCHAR(20),
    start_jo VARCHAR(50),
    end_jo VARCHAR(50),
    office_assignment VARCHAR(255),
    duration VARCHAR(50),
    conforme TEXT,
    fund_charges TEXT,
    office VARCHAR(255),
    -- Additional fields for data that may have extra columns due to commas in quoted text
    extra_field_1 TEXT,
    extra_field_2 TEXT,
    extra_field_3 TEXT,
    extra_field_4 TEXT,
    extra_field_5 TEXT,
    -- Metadata fields
    import_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_processed BOOLEAN DEFAULT FALSE,
    processing_notes TEXT
);

-- Index for performance during transformation
CREATE INDEX idx_staging_jo_number ON staging_csv(jo_number);
CREATE INDEX idx_staging_processed ON staging_csv(is_processed);

-- Comments for field mapping
COMMENT ON TABLE staging_csv IS 'Staging table for raw CSV import from stagingjo.csv';
COMMENT ON COLUMN staging_csv.jo_number IS 'Job Order Number (e.g., AB2024-12-001)';
COMMENT ON COLUMN staging_csv.jo_date IS 'Job Order Date as text (e.g., "December 27, 2024")';
COMMENT ON COLUMN staging_csv.employee_name IS 'Full employee name';
COMMENT ON COLUMN staging_csv.designation IS 'Job designation/position';
COMMENT ON COLUMN staging_csv.daily_rate IS 'Daily rate as text (needs conversion to decimal)';
COMMENT ON COLUMN staging_csv.start_jo IS 'Job Order start date as text';
COMMENT ON COLUMN staging_csv.end_jo IS 'Job Order end date as text';
COMMENT ON COLUMN staging_csv.office_assignment IS 'Office assignment';
COMMENT ON COLUMN staging_csv.duration IS 'Duration information (e.g., "8 hrs./day")';
COMMENT ON COLUMN staging_csv.conforme IS 'Conforme field (often empty)';
COMMENT ON COLUMN staging_csv.fund_charges IS 'Funding source charges description';
COMMENT ON COLUMN staging_csv.office IS 'Office code';
COMMENT ON COLUMN staging_csv.extra_field_1 IS 'Additional field for handling CSV parsing issues';
COMMENT ON COLUMN staging_csv.is_processed IS 'Flag to track if record has been processed into normalized tables';

/*
CSV Import Instructions:
========================

1. Prepare the CSV file:
   - Ensure proper encoding (UTF-8)
   - Handle special characters and commas in quoted fields
   - Run etl/clean.py script if needed for data cleaning

2. Import using PostgreSQL COPY command:

\COPY staging_csv(jo_number, jo_date, employee_name, designation, daily_rate, start_jo, end_jo, office_assignment, duration, conforme, fund_charges, office) 
FROM 'stagingjo.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"', ESCAPE '"');

3. Alternatively, import with error handling for variable columns:

\COPY staging_csv(jo_number, jo_date, employee_name, designation, daily_rate, start_jo, end_jo, office_assignment, duration, conforme, fund_charges, office, extra_field_1, extra_field_2, extra_field_3, extra_field_4, extra_field_5) 
FROM 'stagingjo.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"', ESCAPE '"', FORCE_NULL (conforme, extra_field_1, extra_field_2, extra_field_3, extra_field_4, extra_field_5));

4. Check import results:
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT jo_number) as unique_job_orders,
    COUNT(DISTINCT employee_name) as unique_employees,
    COUNT(*) FILTER (WHERE conforme IS NOT NULL AND conforme != '') as records_with_conforme
FROM staging_csv;

5. Identify data quality issues:
-- Records with potential parsing issues
SELECT * FROM staging_csv WHERE extra_field_1 IS NOT NULL OR extra_field_2 IS NOT NULL;

-- Records with missing critical data
SELECT * FROM staging_csv WHERE jo_number IS NULL OR employee_name IS NULL OR daily_rate IS NULL;

-- Check date format consistency
SELECT DISTINCT jo_date FROM staging_csv ORDER BY jo_date;
SELECT DISTINCT start_jo FROM staging_csv ORDER BY start_jo LIMIT 10;
SELECT DISTINCT end_jo FROM staging_csv ORDER BY end_jo LIMIT 10;
*/