#!/bin/bash
# Example configuration for API probe script
# Copy this to config.sh and customize with your actual data sources

# Embed data sources - files uploaded to your account for retrieval testing
export EMBED_DATA_SOURCES='["your.email@example.edu/2024-09-30/research-notes.txt","your.email@example.edu/2024-09-30/product-data.json"]'

# Assistant data sources - files the assistant can access
export ASSISTANT_DATA_SOURCES='["your.email@example.edu/2024-09-30/sales-data.csv"]'

# Assistant file keys - specific file identifiers
export ASSISTANT_FILE_KEYS='["your.email@example.edu/2024-09-30/customer-feedback.csv"]'

# Model override - use a specific model instead of default
# export MODEL_OVERRIDE="gpt-4o"

# Share target - email for assistant sharing tests
# export SHARE_TARGET="colleague@example.edu"

# State key - for state sharing tests
# export STATE_KEY="some-share-key"

# Usage:
# 1. Copy this file: cp config.example.sh config.sh
# 2. Edit config.sh with your actual data sources
# 3. Source it before running tests: source sample-data/config.sh
# 4. Run the script: ./api-probe.sh --mode all
