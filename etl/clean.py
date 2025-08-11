#!/usr/bin/env python3
"""
CSV Data Cleaning Script for stagingjo.csv
==========================================

This script cleans and preprocesses the stagingjo.csv file to handle:
- Encoding issues (special characters)
- Comma-separated values within quoted fields
- Inconsistent column counts
- Date format standardization
- Rate format cleaning

Usage:
    python etl/clean.py [input_file] [output_file]
    
If no arguments provided, defaults to:
    input: stagingjo.csv
    output: stagingjo_cleaned.csv
"""

import sys
import csv
import re
from pathlib import Path
from typing import List, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class CSVCleaner:
    """Handles cleaning and standardization of job order CSV data."""
    
    def __init__(self):
        self.expected_columns = [
            'jo_number', 'date', 'name', 'designation', 'rate',
            'start_jo', 'end_jo', 'office_assignment', 'duration',
            'conforme', 'fund_charges', 'office'
        ]
        self.stats = {
            'total_rows': 0,
            'cleaned_rows': 0,
            'error_rows': 0,
            'encoding_fixes': 0,
            'date_fixes': 0,
            'rate_fixes': 0
        }
    
    def clean_encoding(self, text: str) -> str:
        """Fix common encoding issues in text."""
        if not text:
            return text
            
        # Common encoding fixes
        replacements = {
            'Ã±': 'ñ',  # ñ character fix
            'Ã¡': 'á',  # á character fix
            'Ã©': 'é',  # é character fix
            'Ã­': 'í',  # í character fix
            'Ã³': 'ó',  # ó character fix
            'Ãº': 'ú',  # ú character fix
            'Ã': 'Ñ',   # Ñ character fix (capital)
            '\u00c3\u00b1': 'ñ',  # Another ñ encoding
            '\u00c3\u00a1': 'á',  # Another á encoding
        }
        
        original_text = text
        for bad_char, good_char in replacements.items():
            text = text.replace(bad_char, good_char)
        
        if text != original_text:
            self.stats['encoding_fixes'] += 1
            
        return text
    
    def clean_date_format(self, date_str: str) -> str:
        """Standardize date formats."""
        if not date_str:
            return date_str
            
        # Remove extra quotes and whitespace
        date_str = date_str.strip(' "\'')
        
        # Handle common date patterns
        # "December 27, 2024" -> standardized format
        month_patterns = {
            'January': '01', 'February': '02', 'March': '03', 'April': '04',
            'May': '05', 'June': '06', 'July': '07', 'August': '08',
            'September': '09', 'October': '10', 'November': '11', 'December': '12'
        }
        
        # Pattern: "Month DD, YYYY"
        pattern = r'(\w+)\s+(\d{1,2}),?\s+(\d{4})'
        match = re.match(pattern, date_str)
        
        if match:
            month_name, day, year = match.groups()
            if month_name in month_patterns:
                # Convert to YYYY-MM-DD format for easier PostgreSQL parsing
                month_num = month_patterns[month_name]
                standardized = f"{year}-{month_num}-{day.zfill(2)}"
                if standardized != date_str:
                    self.stats['date_fixes'] += 1
                return standardized
        
        return date_str
    
    def clean_rate_format(self, rate_str: str) -> str:
        """Clean and standardize rate formats."""
        if not rate_str:
            return rate_str
            
        original_rate = rate_str
        
        # Remove extra quotes and whitespace
        rate_str = rate_str.strip(' "\'')
        
        # Extract numeric value (handle currency symbols)
        rate_match = re.search(r'[\d,]+\.?\d*', rate_str)
        if rate_match:
            cleaned_rate = rate_match.group().replace(',', '')
            if cleaned_rate != original_rate:
                self.stats['rate_fixes'] += 1
            return cleaned_rate
            
        return rate_str
    
    def clean_row(self, row: List[str]) -> List[str]:
        """Clean a single row of data."""
        if len(row) < len(self.expected_columns):
            # Pad with empty strings if too few columns
            row.extend([''] * (len(self.expected_columns) - len(row)))
        elif len(row) > len(self.expected_columns):
            # If too many columns, try to merge the extra ones into fund_charges
            # This often happens when fund_charges contains commas
            if len(row) > 10:  # fund_charges is column 10 (0-indexed)
                # Merge extra columns into fund_charges
                extra_parts = row[10:]
                row[10] = ', '.join(extra_parts)
                row = row[:len(self.expected_columns)]
        
        # Clean each field
        cleaned_row = []
        for i, field in enumerate(row[:len(self.expected_columns)]):
            field = self.clean_encoding(field)
            
            # Apply specific cleaning based on column
            if i in [1, 5, 6]:  # Date columns: date, start_jo, end_jo
                field = self.clean_date_format(field)
            elif i == 4:  # Rate column
                field = self.clean_rate_format(field)
            
            cleaned_row.append(field)
        
        return cleaned_row
    
    def process_file(self, input_file: str, output_file: str) -> None:
        """Process the CSV file and clean the data."""
        input_path = Path(input_file)
        output_path = Path(output_file)
        
        if not input_path.exists():
            raise FileNotFoundError(f"Input file not found: {input_file}")
        
        logger.info(f"Processing {input_file} -> {output_file}")
        
        # Try different encodings
        encodings = ['utf-8', 'utf-8-sig', 'latin1', 'cp1252']
        
        for encoding in encodings:
            try:
                with open(input_path, 'r', encoding=encoding, newline='') as infile:
                    # Try to read a few lines to test encoding
                    sample = infile.read(1000)
                    infile.seek(0)
                    
                    reader = csv.reader(infile)
                    
                    with open(output_path, 'w', encoding='utf-8', newline='') as outfile:
                        writer = csv.writer(outfile, quoting=csv.QUOTE_MINIMAL)
                        
                        # Write header
                        writer.writerow(self.expected_columns)
                        
                        # Process each row
                        for row_num, row in enumerate(reader, 1):
                            self.stats['total_rows'] += 1
                            
                            if row_num == 1:  # Skip original header
                                continue
                                
                            try:
                                cleaned_row = self.clean_row(row)
                                writer.writerow(cleaned_row)
                                self.stats['cleaned_rows'] += 1
                                
                            except Exception as e:
                                logger.warning(f"Error processing row {row_num}: {e}")
                                self.stats['error_rows'] += 1
                                # Write the row as-is with padding
                                padded_row = (row + [''] * len(self.expected_columns))[:len(self.expected_columns)]
                                writer.writerow(padded_row)
                
                logger.info(f"Successfully processed with encoding: {encoding}")
                break
                
            except UnicodeDecodeError:
                logger.info(f"Failed with encoding {encoding}, trying next...")
                continue
            except Exception as e:
                logger.error(f"Error with encoding {encoding}: {e}")
                continue
        else:
            raise ValueError("Could not process file with any supported encoding")
        
        self.print_stats()
    
    def print_stats(self) -> None:
        """Print processing statistics."""
        logger.info("=" * 50)
        logger.info("CLEANING STATISTICS")
        logger.info("=" * 50)
        logger.info(f"Total rows processed: {self.stats['total_rows']}")
        logger.info(f"Successfully cleaned: {self.stats['cleaned_rows']}")
        logger.info(f"Error rows: {self.stats['error_rows']}")
        logger.info(f"Encoding fixes applied: {self.stats['encoding_fixes']}")
        logger.info(f"Date format fixes: {self.stats['date_fixes']}")
        logger.info(f"Rate format fixes: {self.stats['rate_fixes']}")
        logger.info("=" * 50)

def main():
    """Main function to run the CSV cleaner."""
    
    # Parse command line arguments
    if len(sys.argv) == 3:
        input_file = sys.argv[1]
        output_file = sys.argv[2]
    elif len(sys.argv) == 1:
        input_file = 'stagingjo.csv'
        output_file = 'stagingjo_cleaned.csv'
    else:
        print("Usage: python etl/clean.py [input_file] [output_file]")
        print("   or: python etl/clean.py  (uses default files)")
        sys.exit(1)
    
    try:
        cleaner = CSVCleaner()
        cleaner.process_file(input_file, output_file)
        logger.info(f"Cleaning complete! Output saved to: {output_file}")
        
        print("\nNext steps:")
        print("1. Review the cleaned CSV file")
        print("2. Import into PostgreSQL using staging.sql")
        print("3. Run transform.sql to populate normalized tables")
        print("4. Check data quality with validation queries")
        
    except Exception as e:
        logger.error(f"Error processing file: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()