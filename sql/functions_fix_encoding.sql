-- Functions for fixing encoding issues in PostgreSQL
-- Handles common character encoding problems found in CSV imports

-- ============================================================================
-- CHARACTER ENCODING FIX FUNCTIONS
-- ============================================================================

-- Main function to fix common encoding issues
CREATE OR REPLACE FUNCTION fix_encoding(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Apply common encoding fixes
    RETURN fix_spanish_characters(
        fix_common_utf8_issues(
            fix_special_characters(input_text)
        )
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Fix common UTF-8 encoding issues
CREATE OR REPLACE FUNCTION fix_common_utf8_issues(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Replace common UTF-8 encoding errors
    RETURN REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(input_text, 
                                'Ã±', 'ñ'),  -- ñ character
                            'Ã¡', 'á'),     -- á character
                        'Ã©', 'é'),         -- é character
                    'Ã­', 'í'),             -- í character
                'Ã³', 'ó'),                 -- ó character
            'Ãº', 'ú'),                     -- ú character
        'Ã', 'Ñ'                          -- Ñ character (capital)
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Fix Spanish and Filipino character issues
CREATE OR REPLACE FUNCTION fix_spanish_characters(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Fix common Spanish/Filipino character encoding issues
    RETURN REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(input_text,
                                            'Ã±', 'ñ'),     -- eñe
                                        'Ã'', 'Ñ'),        -- capital eñe
                                    'Ã¡', 'á'),            -- a with acute
                                'Ã©', 'é'),                -- e with acute
                            'Ã­', 'í'),                    -- i with acute
                        'Ã³', 'ó'),                        -- o with acute
                    'Ãº', 'ú'),                            -- u with acute
                'Ã', 'Á'),                                 -- capital A with acute
                'Ã‰', 'É'),                                -- capital E with acute
            'Ã', 'Í'),                                     -- capital I with acute
        'Ã"', 'Ó'                                          -- capital O with acute
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Fix special characters and symbols
CREATE OR REPLACE FUNCTION fix_special_characters(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Fix common special character issues
    RETURN REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(input_text,
                                '"', '"'),          -- Smart quotes to regular
                            '"', '"'),             -- Smart quotes to regular
                        ''', ''''),                -- Smart apostrophe
                    '…', '...'),                   -- Ellipsis
                '–', '-'),                         -- En dash to hyphen
            '—', '-'),                             -- Em dash to hyphen
        '�', ''                                    -- Remove replacement character
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Clean and standardize name formatting
CREATE OR REPLACE FUNCTION clean_name_format(input_name TEXT)
RETURNS TEXT AS $$
BEGIN
    IF input_name IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Apply encoding fixes first
    input_name := fix_encoding(input_name);
    
    -- Trim whitespace
    input_name := TRIM(input_name);
    
    -- Remove multiple spaces
    input_name := REGEXP_REPLACE(input_name, '\s+', ' ', 'g');
    
    -- Handle common name format issues
    -- Remove parenthetical suffixes like "(SC)" unless they're part of the actual name
    -- Keep them for now as they might be significant designations
    
    -- Proper case formatting - capitalize first letter of each word
    input_name := INITCAP(input_name);
    
    -- Fix common capitalization issues with particles
    input_name := REPLACE(input_name, ' De ', ' de ');
    input_name := REPLACE(input_name, ' Del ', ' del ');
    input_name := REPLACE(input_name, ' La ', ' la ');
    input_name := REPLACE(input_name, ' Los ', ' los ');
    input_name := REPLACE(input_name, ' Las ', ' las ');
    input_name := REPLACE(input_name, ' Y ', ' y ');
    
    RETURN input_name;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- BATCH ENCODING FIX PROCEDURES
-- ============================================================================

-- Procedure to fix encoding in all employee names
CREATE OR REPLACE PROCEDURE fix_employee_names_encoding()
LANGUAGE plpgsql AS $$
DECLARE
    fix_count INTEGER := 0;
BEGIN
    -- Update employee names with encoding fixes
    UPDATE employees 
    SET full_name = clean_name_format(full_name)
    WHERE full_name != clean_name_format(full_name);
    
    GET DIAGNOSTICS fix_count = ROW_COUNT;
    
    RAISE NOTICE 'Fixed encoding for % employee names', fix_count;
END;
$$;

-- Procedure to fix encoding in staging data
CREATE OR REPLACE PROCEDURE fix_staging_encoding()
LANGUAGE plpgsql AS $$
DECLARE
    fix_count INTEGER := 0;
BEGIN
    -- Fix employee names
    UPDATE staging_csv 
    SET employee_name = clean_name_format(employee_name)
    WHERE employee_name != clean_name_format(employee_name);
    
    GET DIAGNOSTICS fix_count = ROW_COUNT;
    RAISE NOTICE 'Fixed encoding for % employee names in staging', fix_count;
    
    -- Fix office names
    UPDATE staging_csv 
    SET office_assignment = fix_encoding(office_assignment),
        office = fix_encoding(office)
    WHERE office_assignment != fix_encoding(office_assignment) 
       OR office != fix_encoding(office);
    
    GET DIAGNOSTICS fix_count = ROW_COUNT;
    RAISE NOTICE 'Fixed encoding for % office names in staging', fix_count;
    
    -- Fix designation names
    UPDATE staging_csv 
    SET designation = fix_encoding(designation)
    WHERE designation != fix_encoding(designation);
    
    GET DIAGNOSTICS fix_count = ROW_COUNT;
    RAISE NOTICE 'Fixed encoding for % designations in staging', fix_count;
    
    -- Fix fund charges
    UPDATE staging_csv 
    SET fund_charges = fix_encoding(fund_charges)
    WHERE fund_charges != fix_encoding(fund_charges);
    
    GET DIAGNOSTICS fix_count = ROW_COUNT;
    RAISE NOTICE 'Fixed encoding for % fund charges in staging', fix_count;
END;
$$;

-- ============================================================================
-- VALIDATION FUNCTIONS
-- ============================================================================

-- Function to detect potential encoding issues
CREATE OR REPLACE FUNCTION detect_encoding_issues(input_text TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF input_text IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Check for common encoding problem patterns
    RETURN (
        input_text ~ 'Ã±|Ã¡|Ã©|Ã­|Ã³|Ãº|Ã|Ã‰|Ã|Ã"|Ã|�|â€|â€™|â€œ|â€'
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Query to find records with potential encoding issues
/*
Example usage:

-- Find employees with encoding issues
SELECT employee_id, full_name, 
       fix_encoding(full_name) as corrected_name
FROM employees 
WHERE detect_encoding_issues(full_name);

-- Find staging records with encoding issues
SELECT staging_id, employee_name, office_assignment, designation, fund_charges
FROM staging_csv 
WHERE detect_encoding_issues(employee_name) 
   OR detect_encoding_issues(office_assignment)
   OR detect_encoding_issues(designation)
   OR detect_encoding_issues(fund_charges);

-- Apply fixes to all tables
CALL fix_staging_encoding();
CALL fix_employee_names_encoding();

-- Fix office names
UPDATE offices SET office_name = fix_encoding(office_name) 
WHERE detect_encoding_issues(office_name);

-- Fix designation names
UPDATE designations SET designation_name = fix_encoding(designation_name) 
WHERE detect_encoding_issues(designation_name);

-- Fix funding source descriptions
UPDATE funding_sources SET funding_description = fix_encoding(funding_description) 
WHERE detect_encoding_issues(funding_description);
*/

-- ============================================================================
-- COMMENTS AND DOCUMENTATION
-- ============================================================================

COMMENT ON FUNCTION fix_encoding(TEXT) IS 'Main function to fix common encoding issues in text data';
COMMENT ON FUNCTION fix_common_utf8_issues(TEXT) IS 'Fixes common UTF-8 encoding errors';
COMMENT ON FUNCTION fix_spanish_characters(TEXT) IS 'Fixes Spanish and Filipino character encoding issues';
COMMENT ON FUNCTION fix_special_characters(TEXT) IS 'Fixes special characters and symbols';
COMMENT ON FUNCTION clean_name_format(TEXT) IS 'Cleans and standardizes name formatting with proper capitalization';
COMMENT ON FUNCTION detect_encoding_issues(TEXT) IS 'Detects potential encoding issues in text';
COMMENT ON PROCEDURE fix_employee_names_encoding() IS 'Batch procedure to fix encoding in all employee names';
COMMENT ON PROCEDURE fix_staging_encoding() IS 'Batch procedure to fix encoding in staging table data';