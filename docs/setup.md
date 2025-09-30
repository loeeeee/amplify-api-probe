# API Probe Setup Guide

This guide will help you set up and run the `api-probe.sh` script to test the Amplify API.

## Prerequisites

The script requires the following command-line tools:

- **bash** (version 4.0 or later)
- **curl** - for making HTTP requests
- **jq** - for JSON parsing and validation

### Installing Prerequisites

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install curl jq
```

**On macOS:**
```bash
brew install curl jq
```

**On Fedora/RHEL:**
```bash
sudo dnf install curl jq
```

## Configuration

### 1. Create the Secrets Directory

The script looks for API credentials in the `secrets/` directory:

```bash
mkdir -p secrets
```

### 2. Add Your API Token

Create a file containing your Amplify API authentication token:

```bash
echo "your-api-token-here" > secrets/token.txt
```

**Important:** Make sure there are no extra newlines or spaces in this file.

### 3. Add Your API Base URL

Create a file containing the API base URL:

```bash
echo "https://your-api-endpoint.com" > secrets/baseurl.txt
```

### 4. Protect Your Secrets

Ensure the secrets directory is not committed to version control:

```bash
# The .gitignore should already contain:
secrets/
```

And restrict file permissions:

```bash
chmod 600 secrets/token.txt secrets/baseurl.txt
```

## Sample Data (Battery Included!)

The script comes with sample data files in the `sample-data/` directory, making it easy to test without preparing your own files.

### What's Included

The script includes ready-to-use sample files:

- **`sales-data.csv`** - Sample sales transaction data (16 rows)
- **`customer-feedback.csv`** - Customer feedback and ratings (10 rows)
- **`research-notes.txt`** - Research notes for document analysis
- **`product-data.json`** - Structured product catalog data
- **`config.example.sh`** - Example configuration for data sources

### Automatic Fallback

**The script automatically uses sample data when you don't provide your own!**

When running file upload tests without specifying `--sample-file`, the script will:
1. First check if you provided a `--sample-file` argument
2. If not, look for `sample-data/sales-data.csv`
3. If that doesn't exist, create a minimal temporary CSV

This means you can run the script right away without any preparation:

```bash
# This will automatically use sample-data/sales-data.csv
./api-probe.sh --mode files
```

### Using Different Sample Files

Override the default with any sample file:

```bash
./api-probe.sh --mode files --sample-file sample-data/customer-feedback.csv
./api-probe.sh --mode files --sample-file sample-data/research-notes.txt
```

### Configuring Data Sources

For embedding and assistant tests, you'll need data sources from your account. Use the example config:

```bash
# Copy the example config
cp sample-data/config.example.sh sample-data/config.sh

# Edit with your actual data sources
nano sample-data/config.sh

# Source it before running
source sample-data/config.sh
./api-probe.sh --mode all
```

See `sample-data/README.md` for more details on the included files.

## Running the Script

### Basic Usage

Run the default smoke tests:

```bash
./api-probe.sh
```

Or explicitly specify smoke mode:

```bash
./api-probe.sh --mode smoke
```

### Test Modes

The script supports different testing modes:

#### Smoke Tests (Quick Validation)
Tests essential endpoints: available models, chat, and file tags list.

```bash
./api-probe.sh --mode smoke
```

#### Files Tests
Tests file upload, query, and tag management operations.

```bash
./api-probe.sh --mode files
```

#### Embedding Tests
Tests the embedding/retrieval endpoint (requires data sources).

```bash
./api-probe.sh --mode embed --embed-data-sources '["user@example.edu/path/file.json"]'
```

#### Assistant Tests
Tests assistant creation, chat, sharing, and deletion.

```bash
./api-probe.sh --mode assistants
```

#### All Tests
Runs all available tests (smoke, embed, files, assistants).

```bash
./api-probe.sh --mode all
```

### Advanced Options

#### Using a Custom Token or URL

Override the secrets files:

```bash
./api-probe.sh --token "your-token" --base-url "https://api.example.com"
```

Or use a token file:

```bash
./api-probe.sh --token-file ~/.amplify_token
```

#### Upload a Specific File

```bash
./api-probe.sh --mode files --sample-file ./path/to/data.csv
```

#### Enable Destructive Operations

By default, delete operations are skipped. To enable them:

```bash
./api-probe.sh --mode all --destructive
```

**Warning:** This will delete created assistants, threads, and tags during testing.

#### Custom Timeout

Set a custom timeout for API requests (default: 60 seconds):

```bash
./api-probe.sh --timeout 120
```

#### Dry Run Mode

Test the script without making actual API calls:

```bash
./api-probe.sh --dry-run
```

## Understanding the Output

### Directory Structure

After running, the script creates a `probe-results/` directory:

```
probe-results/
├── requests/          # JSON request bodies sent to API
├── responses/         # JSON responses received from API
└── headers/           # HTTP response headers
```

Each test creates three files with the same base name:
- `{test-name}.request.json` - The request payload
- `{test-name}.response.json` - The API response
- `{test-name}.headers.txt` - HTTP headers

### Test Results

The script outputs test results in real-time:

```
[INFO] Running smoke tests
[INFO] PASS: available_models .data.models array
[INFO] Selected model id: gpt-4o-mini
[INFO] PASS: chat string answer
[INFO] PASS: files-tags-list tags array
[INFO] Tests passed: 3
[INFO] Tests failed: 0
```

### Exit Codes

- **0** - All tests passed
- **1** - One or more tests failed
- **2** - Configuration error (missing token, unknown argument, etc.)
- **127** - Missing required command (curl or jq)

## Troubleshooting

### "Missing required command: jq"

Install `jq` using your package manager (see Prerequisites above).

### "No token provided"

Ensure you've created `secrets/token.txt` with your API token, or pass `--token` explicitly.

### HTTP 401 Errors

Your API token may be invalid or expired. Check `secrets/token.txt` and verify the token is correct.

### HTTP 400 Errors

Check the request/response files in `probe-results/` to see what the API rejected. Common issues:
- Missing required fields
- Invalid data format
- Tenant-specific requirements

### Tests Are Skipped

Some tests require additional configuration:
- **Embedding tests**: Provide `--embed-data-sources`
- **Assistant chat**: Requires successful assistant creation first
- **Delete operations**: Require `--destructive` flag

## Examples

### Quick API Health Check

```bash
./api-probe.sh --mode smoke
```

### Full Test Suite with Cleanup

```bash
./api-probe.sh --mode all --destructive
```

### Test File Operations

```bash
./api-probe.sh --mode files --sample-file my-data.csv
```

### Test with Custom Data Sources

```bash
./api-probe.sh --mode all \
  --embed-data-sources '["user@example.edu/2024/data.json"]' \
  --assistant-data-sources '["user@example.edu/2024/data.json"]'
```

### Production Environment Testing

```bash
./api-probe.sh \
  --base-url "https://api.production.example.com" \
  --token-file ~/.amplify_prod_token \
  --mode smoke \
  --timeout 120
```

## Next Steps

- Review the generated files in `probe-results/` to understand API request/response formats
- Use the request files as templates for your own API integrations
- Integrate the script into your CI/CD pipeline for automated API testing

## Getting Help

View all available options:

```bash
./api-probe.sh --help
```

Check the script version:

```bash
./api-probe.sh --version
```
