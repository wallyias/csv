-- Advanced Working Day Calculation Functions
-- Provides sophisticated working day calculations excluding holidays
-- Supports employee-specific schedules and fiscal year computations

-- ============================================================================
-- CORE WORKING DAY FUNCTIONS
-- ============================================================================

-- Main working days calculation function (excluding holidays)
CREATE OR REPLACE FUNCTION working_days(start_date DATE, end_date DATE)
RETURNS INTEGER AS $$
DECLARE
    working_day_count INTEGER := 0;
    current_date DATE;
BEGIN
    -- Validate input dates
    IF start_date IS NULL OR end_date IS NULL THEN
        RETURN 0;
    END IF;
    
    IF start_date > end_date THEN
        RETURN 0;
    END IF;
    
    -- Count working days (Monday through Friday) excluding holidays
    SELECT COUNT(*)::INTEGER INTO working_day_count
    FROM generate_series(start_date, end_date, '1 day'::interval) AS d
    WHERE 
        -- Monday (1) through Friday (5)
        extract(dow from d) BETWEEN 1 AND 5
        -- Exclude holidays
        AND d NOT IN (
            SELECT holiday_date 
            FROM holidays 
            WHERE holiday_date BETWEEN start_date AND end_date
              AND is_active = TRUE
        );
    
    RETURN COALESCE(working_day_count, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- Working days calculation with holiday type filtering
CREATE OR REPLACE FUNCTION working_days_by_holiday_type(
    start_date DATE, 
    end_date DATE,
    exclude_holiday_types TEXT[] DEFAULT ARRAY['PUBLIC', 'REGIONAL', 'SPECIAL']
)
RETURNS INTEGER AS $$
DECLARE
    working_day_count INTEGER := 0;
BEGIN
    -- Validate input dates
    IF start_date IS NULL OR end_date IS NULL THEN
        RETURN 0;
    END IF;
    
    IF start_date > end_date THEN
        RETURN 0;
    END IF;
    
    -- Count working days excluding specified holiday types
    SELECT COUNT(*)::INTEGER INTO working_day_count
    FROM generate_series(start_date, end_date, '1 day'::interval) AS d
    WHERE 
        -- Monday (1) through Friday (5)
        extract(dow from d) BETWEEN 1 AND 5
        -- Exclude specified holiday types
        AND d NOT IN (
            SELECT holiday_date 
            FROM holidays 
            WHERE holiday_date BETWEEN start_date AND end_date
              AND is_active = TRUE
              AND holiday_type = ANY(exclude_holiday_types)
        );
    
    RETURN COALESCE(working_day_count, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- FISCAL YEAR WORKING DAY FUNCTIONS
-- ============================================================================

-- Calculate working days within a specific fiscal year
CREATE OR REPLACE FUNCTION working_days_in_fiscal_year(
    start_date DATE, 
    end_date DATE, 
    fiscal_year INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    fy_start_date DATE;
    fy_end_date DATE;
    effective_start DATE;
    effective_end DATE;
BEGIN
    -- Define fiscal year boundaries (assuming calendar year)
    -- Adjust these dates based on your organization's fiscal year
    fy_start_date := DATE(fiscal_year || '-01-01');
    fy_end_date := DATE(fiscal_year || '-12-31');
    
    -- Calculate effective date range (intersection of job period and fiscal year)
    effective_start := GREATEST(start_date, fy_start_date);
    effective_end := LEAST(end_date, fy_end_date);
    
    -- Return 0 if no overlap
    IF effective_start > effective_end THEN
        RETURN 0;
    END IF;
    
    -- Calculate working days in the effective period
    RETURN working_days(effective_start, effective_end);
END;
$$ LANGUAGE plpgsql STABLE;

-- Calculate working days split by fiscal year for cross-year assignments
CREATE OR REPLACE FUNCTION working_days_by_fiscal_year(
    start_date DATE, 
    end_date DATE
)
RETURNS TABLE(fiscal_year INTEGER, working_days_count INTEGER) AS $$
DECLARE
    start_year INTEGER;
    end_year INTEGER;
    current_year INTEGER;
BEGIN
    -- Get the range of years covered
    start_year := EXTRACT(YEAR FROM start_date);
    end_year := EXTRACT(YEAR FROM end_date);
    
    -- Generate working days for each fiscal year in the range
    FOR current_year IN start_year..end_year LOOP
        fiscal_year := current_year;
        working_days_count := working_days_in_fiscal_year(start_date, end_date, current_year);
        
        -- Only return years with working days
        IF working_days_count > 0 THEN
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- EMPLOYEE-SPECIFIC WORKING DAY FUNCTIONS
-- ============================================================================

-- Employee working schedule table (for future expansion)
-- Currently using generic Monday-Friday schedule
/*
CREATE TABLE employee_schedules (
    schedule_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id),
    effective_from DATE NOT NULL,
    effective_to DATE,
    monday BOOLEAN DEFAULT TRUE,
    tuesday BOOLEAN DEFAULT TRUE,
    wednesday BOOLEAN DEFAULT TRUE,
    thursday BOOLEAN DEFAULT TRUE,
    friday BOOLEAN DEFAULT TRUE,
    saturday BOOLEAN DEFAULT FALSE,
    sunday BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
*/

-- Placeholder function for employee-specific working days
-- Currently implements generic Monday-Friday schedule
CREATE OR REPLACE FUNCTION employee_working_days(
    employee_id INTEGER,
    start_date DATE, 
    end_date DATE
)
RETURNS INTEGER AS $$
BEGIN
    -- Currently using generic Monday-Friday schedule for all employees
    -- Future enhancement: implement employee-specific schedules
    
    -- For now, return standard working days calculation
    RETURN working_days(start_date, end_date);
    
    /*
    Future implementation with employee schedules:
    
    DECLARE
        schedule_working_days INTEGER := 0;
        current_date DATE;
        schedule_rec RECORD;
    BEGIN
        -- Get employee schedule for the period
        SELECT * INTO schedule_rec
        FROM employee_schedules 
        WHERE employee_id = employee_working_days.employee_id
          AND effective_from <= start_date
          AND (effective_to IS NULL OR effective_to >= end_date)
        ORDER BY effective_from DESC
        LIMIT 1;
        
        -- If no specific schedule, use default Monday-Friday
        IF NOT FOUND THEN
            RETURN working_days(start_date, end_date);
        END IF;
        
        -- Count working days based on employee schedule
        FOR current_date IN 
            SELECT d::DATE
            FROM generate_series(start_date, end_date, '1 day'::interval) AS d
            WHERE d NOT IN (SELECT holiday_date FROM holidays WHERE is_active = TRUE)
        LOOP
            -- Check if the day is a working day for this employee
            CASE EXTRACT(dow FROM current_date)
                WHEN 1 THEN -- Monday
                    IF schedule_rec.monday THEN
                        schedule_working_days := schedule_working_days + 1;
                    END IF;
                WHEN 2 THEN -- Tuesday
                    IF schedule_rec.tuesday THEN
                        schedule_working_days := schedule_working_days + 1;
                    END IF;
                -- ... continue for other days
            END CASE;
        END LOOP;
        
        RETURN schedule_working_days;
    */
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- COST CALCULATION HELPER FUNCTIONS
-- ============================================================================

-- Calculate total estimated cost for a job assignment
CREATE OR REPLACE FUNCTION calculate_assignment_cost(
    start_date DATE,
    end_date DATE,
    daily_rate DECIMAL(10,2)
)
RETURNS DECIMAL(12,2) AS $$
DECLARE
    total_working_days INTEGER;
    total_cost DECIMAL(12,2);
BEGIN
    -- Calculate working days
    total_working_days := working_days(start_date, end_date);
    
    -- Calculate total cost
    total_cost := total_working_days * daily_rate;
    
    RETURN COALESCE(total_cost, 0.00);
END;
$$ LANGUAGE plpgsql STABLE;

-- Calculate cost split by fiscal year
CREATE OR REPLACE FUNCTION calculate_assignment_cost_by_year(
    start_date DATE,
    end_date DATE,
    daily_rate DECIMAL(10,2)
)
RETURNS TABLE(
    fiscal_year INTEGER, 
    working_days_count INTEGER, 
    year_cost DECIMAL(12,2)
) AS $$
DECLARE
    year_rec RECORD;
BEGIN
    -- Get working days by fiscal year
    FOR year_rec IN 
        SELECT * FROM working_days_by_fiscal_year(start_date, end_date)
    LOOP
        fiscal_year := year_rec.fiscal_year;
        working_days_count := year_rec.working_days_count;
        year_cost := working_days_count * daily_rate;
        
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if a specific date is a working day
CREATE OR REPLACE FUNCTION is_working_day(check_date DATE)
RETURNS BOOLEAN AS $$
BEGIN
    -- Check if it's a weekday (Monday-Friday)
    IF extract(dow from check_date) NOT BETWEEN 1 AND 5 THEN
        RETURN FALSE;
    END IF;
    
    -- Check if it's not a holiday
    IF EXISTS (
        SELECT 1 FROM holidays 
        WHERE holiday_date = check_date AND is_active = TRUE
    ) THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;

-- Get next working day after a given date
CREATE OR REPLACE FUNCTION next_working_day(from_date DATE)
RETURNS DATE AS $$
DECLARE
    next_date DATE := from_date + 1;
BEGIN
    -- Find the next working day
    WHILE NOT is_working_day(next_date) LOOP
        next_date := next_date + 1;
    END LOOP;
    
    RETURN next_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- Get previous working day before a given date
CREATE OR REPLACE FUNCTION previous_working_day(from_date DATE)
RETURNS DATE AS $$
DECLARE
    prev_date DATE := from_date - 1;
BEGIN
    -- Find the previous working day
    WHILE NOT is_working_day(prev_date) LOOP
        prev_date := prev_date - 1;
    END LOOP;
    
    RETURN prev_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

-- Ensure holidays table has proper indexes for performance
-- (These should already exist from schema.sql, but included for completeness)
/*
CREATE INDEX IF NOT EXISTS idx_holidays_date ON holidays(holiday_date);
CREATE INDEX IF NOT EXISTS idx_holidays_active ON holidays(is_active);
CREATE INDEX IF NOT EXISTS idx_holidays_type ON holidays(holiday_type);
*/

-- ============================================================================
-- FUNCTION DOCUMENTATION
-- ============================================================================

COMMENT ON FUNCTION working_days(DATE, DATE) IS 'Calculate working days (Mon-Fri) excluding holidays between two dates';
COMMENT ON FUNCTION working_days_by_holiday_type(DATE, DATE, TEXT[]) IS 'Calculate working days excluding specific holiday types';
COMMENT ON FUNCTION working_days_in_fiscal_year(DATE, DATE, INTEGER) IS 'Calculate working days within a specific fiscal year';
COMMENT ON FUNCTION working_days_by_fiscal_year(DATE, DATE) IS 'Split working days calculation by fiscal year for cross-year periods';
COMMENT ON FUNCTION employee_working_days(INTEGER, DATE, DATE) IS 'Calculate working days for specific employee (placeholder for custom schedules)';
COMMENT ON FUNCTION calculate_assignment_cost(DATE, DATE, DECIMAL) IS 'Calculate total estimated cost: working_days * daily_rate';
COMMENT ON FUNCTION calculate_assignment_cost_by_year(DATE, DATE, DECIMAL) IS 'Calculate cost split by fiscal year';
COMMENT ON FUNCTION is_working_day(DATE) IS 'Check if a specific date is a working day';
COMMENT ON FUNCTION next_working_day(DATE) IS 'Get the next working day after a given date';
COMMENT ON FUNCTION previous_working_day(DATE) IS 'Get the previous working day before a given date';

/*
Example Usage:
==============

-- Basic working days calculation
SELECT working_days('2024-01-01', '2024-01-31') as jan_working_days;

-- Calculate cost for an assignment
SELECT calculate_assignment_cost('2024-01-01', '2024-01-31', 407.27) as total_cost;

-- Get cost split by fiscal year for cross-year assignment
SELECT * FROM calculate_assignment_cost_by_year('2024-12-01', '2025-02-28', 407.27);

-- Check working days for each fiscal year
SELECT * FROM working_days_by_fiscal_year('2024-12-01', '2025-02-28');

-- Populate holidays table
INSERT INTO holidays (holiday_date, holiday_name, holiday_type) VALUES 
('2024-01-01', 'New Year''s Day', 'PUBLIC'),
('2024-12-25', 'Christmas Day', 'PUBLIC'),
('2024-12-30', 'Rizal Day', 'PUBLIC'),
('2025-01-01', 'New Year''s Day', 'PUBLIC');
*/