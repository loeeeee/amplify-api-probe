# Sample Data Files

This directory contains sample data files for testing the API probe script without requiring your own data.

## Available Files

### CSV Files

**`sales-data.csv`**
- Sample sales transaction data with 16 rows
- Columns: Date, Product, Quantity, Revenue, Region, SalesRep
- Use for: File upload tests, data analysis, assistant code interpreter

**`customer-feedback.csv`**
- Customer feedback and ratings data with 10 rows
- Columns: CustomerID, FeedbackDate, Rating, Category, Comment
- Use for: Text analysis, sentiment analysis, file upload tests

### Text Files

**`research-notes.txt`**
- Sample research notes about AI capabilities
- Formatted with sections and bullet points
- Use for: Document analysis, text retrieval, embedding tests

### JSON Files

**`product-data.json`**
- Product catalog with 3 products
- Structured data with metadata
- Use for: JSON parsing, structured data tests

## Using Sample Data with the Script

The script automatically uses sample data when available:

### File Upload Tests
```bash
# Uses sample-data/sales-data.csv by default if no --sample-file is specified
./api-probe.sh --mode files
```

### Specify a Different Sample File
```bash
./api-probe.sh --mode files --sample-file sample-data/customer-feedback.csv
```

### Multiple File Tests
Test with all sample files:
```bash
for file in sample-data/*.csv; do
  ./api-probe.sh --mode files --sample-file "$file"
done
```

## Data Sources Configuration

For embedding and assistant tests, you'll need to specify data sources that exist in your account. Sample data sources would look like:

```bash
./api-probe.sh --mode embed \
  --embed-data-sources '["your.email@example.edu/2024-09-30/research-notes.txt"]'
```

Create a local config file to avoid typing these repeatedly:

**`sample-data/config.example.sh`**
```bash
#!/bin/bash
# Example configuration for data sources
export EMBED_DATA_SOURCES='["user@example.edu/2024/file1.json"]'
export ASSISTANT_DATA_SOURCES='["user@example.edu/2024/file2.csv"]'
export ASSISTANT_FILE_KEYS='["user@example.edu/2024/file3.txt"]'
```

Then source it before running tests:
```bash
source sample-data/config.sh
./api-probe.sh --mode all
```

## Adding Your Own Sample Data

Feel free to add more sample files to this directory:

1. Keep files small (< 1MB) for quick uploads
2. Use realistic but non-sensitive data
3. Include a variety of file formats (.csv, .txt, .json, .pdf)
4. Document what each file is for

## Notes

- These files are for **testing purposes only**
- They contain fictional data
- Files are safe to upload to test environments
- Do not contain any sensitive or proprietary information
