-- PostgreSQL Normalization Schema for Job Order Management System
-- This schema provides normalized tables for job orders, employees, and cost tracking
-- with support for funding allocation and working day calculations

-- Enable UUID extension for unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Status enumeration for consistent status handling
CREATE TYPE status_type AS ENUM ('ACTIVE', 'RESERVED', 'CANCELLED');

-- ============================================================================
-- LOOKUP TABLES
-- ============================================================================

-- Offices lookup table
CREATE TABLE offices (
    office_id SERIAL PRIMARY KEY,
    office_code VARCHAR(20) UNIQUE NOT NULL,
    office_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Designations lookup table
CREATE TABLE designations (
    designation_id SERIAL PRIMARY KEY,
    designation_name VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Funding sources lookup table
CREATE TABLE funding_sources (
    funding_source_id SERIAL PRIMARY KEY,
    funding_code VARCHAR(100) UNIQUE NOT NULL,
    funding_description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- CORE ENTITY TABLES
-- ============================================================================

-- Employees table
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    employee_uuid UUID DEFAULT uuid_generate_v4() UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    status status_type DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Job orders table
CREATE TABLE job_orders (
    job_order_id SERIAL PRIMARY KEY,
    jo_number VARCHAR(50) UNIQUE NOT NULL,
    jo_date DATE NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    office_id INTEGER REFERENCES offices(office_id),
    status status_type DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- ASSIGNMENT AND ALLOCATION TABLES
-- ============================================================================

-- Job order employee assignments (many-to-many relationship)
CREATE TABLE job_order_assignments (
    assignment_id SERIAL PRIMARY KEY,
    job_order_id INTEGER REFERENCES job_orders(job_order_id),
    employee_id INTEGER REFERENCES employees(employee_id),
    designation_id INTEGER REFERENCES designations(designation_id),
    daily_rate DECIMAL(10,2) NOT NULL,
    duration_hours VARCHAR(50), -- e.g., "8 hrs./day"
    office_assignment_id INTEGER REFERENCES offices(office_id),
    conforme TEXT,
    status status_type DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(job_order_id, employee_id)
);

-- Funding source allocations for job orders
CREATE TABLE funding_source_allocations (
    allocation_id SERIAL PRIMARY KEY,
    job_order_id INTEGER REFERENCES job_orders(job_order_id),
    funding_source_id INTEGER REFERENCES funding_sources(funding_source_id),
    allocation_percentage DECIMAL(5,2) DEFAULT 100.00 CHECK (allocation_percentage >= 0 AND allocation_percentage <= 100),
    fiscal_year INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(job_order_id, funding_source_id, fiscal_year)
);

-- ============================================================================
-- HOLIDAY CALENDAR TABLE
-- ============================================================================

-- Holiday calendar for working day calculations
CREATE TABLE holidays (
    holiday_id SERIAL PRIMARY KEY,
    holiday_date DATE UNIQUE NOT NULL,
    holiday_name VARCHAR(255) NOT NULL,
    holiday_type VARCHAR(50) DEFAULT 'PUBLIC', -- PUBLIC, REGIONAL, SPECIAL
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Job order indexes
CREATE INDEX idx_job_orders_jo_number ON job_orders(jo_number);
CREATE INDEX idx_job_orders_dates ON job_orders(start_date, end_date);
CREATE INDEX idx_job_orders_status ON job_orders(status);

-- Employee indexes
CREATE INDEX idx_employees_name ON employees(full_name);
CREATE INDEX idx_employees_status ON employees(status);

-- Assignment indexes
CREATE INDEX idx_assignments_job_order ON job_order_assignments(job_order_id);
CREATE INDEX idx_assignments_employee ON job_order_assignments(employee_id);
CREATE INDEX idx_assignments_status ON job_order_assignments(status);

-- Funding allocation indexes
CREATE INDEX idx_allocations_job_order ON funding_source_allocations(job_order_id);
CREATE INDEX idx_allocations_funding_source ON funding_source_allocations(funding_source_id);
CREATE INDEX idx_allocations_fiscal_year ON funding_source_allocations(fiscal_year);

-- Holiday indexes
CREATE INDEX idx_holidays_date ON holidays(holiday_date);
CREATE INDEX idx_holidays_active ON holidays(is_active);

-- ============================================================================
-- BASIC WORKING DAYS FUNCTION
-- ============================================================================

-- Basic working days calculation (detailed functions in sql/working_day_functions.sql)
CREATE OR REPLACE FUNCTION basic_working_days(start_date DATE, end_date DATE)
RETURNS INTEGER AS $$
BEGIN
    -- Simple weekday count, excludes Saturday and Sunday
    -- More sophisticated logic with holiday exclusions in working_day_functions.sql
    RETURN (
        SELECT COUNT(*)::INTEGER
        FROM generate_series(start_date, end_date, '1 day'::interval) AS d
        WHERE extract(dow from d) BETWEEN 1 AND 5  -- Monday to Friday
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- TRIGGERS FOR UPDATED_AT TIMESTAMPS
-- ============================================================================

-- Generic trigger function for updating timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers to relevant tables
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_job_orders_updated_at BEFORE UPDATE ON job_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assignments_updated_at BEFORE UPDATE ON job_order_assignments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SAMPLE DATA COMMENTS
-- ============================================================================

/*
To populate funding_source_allocations after data import:

INSERT INTO funding_source_allocations (job_order_id, funding_source_id, allocation_percentage, fiscal_year)
SELECT 
    jo.job_order_id,
    fs.funding_source_id,
    100.00,  -- Default 100% allocation
    EXTRACT(YEAR FROM jo.start_date) as fiscal_year
FROM job_orders jo
JOIN job_order_assignments joa ON jo.job_order_id = joa.job_order_id
JOIN funding_sources fs ON fs.funding_code = (
    -- Match funding from the original data transformation
    SELECT DISTINCT fund_charges FROM staging_csv s WHERE s.jo_number = jo.jo_number LIMIT 1
)
WHERE jo.status IN ('ACTIVE', 'RESERVED')
ON CONFLICT (job_order_id, funding_source_id, fiscal_year) DO NOTHING;

Sample holiday data:
INSERT INTO holidays (holiday_date, holiday_name) VALUES 
('2024-01-01', 'New Year''s Day'),
('2024-12-25', 'Christmas Day'),
('2024-12-30', 'Rizal Day');
*/

-- Schema creation complete
-- Note: Heavy working day logic and cost reporting views are separated into:
-- - sql/working_day_functions.sql (for complex working day calculations)
-- - sql/views_cost_reporting.sql (for comprehensive reporting views)