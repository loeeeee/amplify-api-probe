#!/usr/bin/env bash

set -euo pipefail

# Amplify API test harness using curl
# - Hits key endpoints described in amplify-docs/api-better.md
# - Validates basic response shapes with jq
# - Writes request/response artifacts for developer docs

VERSION="1.0.0"

print_usage() {
  cat <<'USAGE'
Amplify API test script

Usage:
  scripts/amplify-api-test.sh \
    [--token TOKEN | --token-file PATH | env AMPLIFY_API_TOKEN] \
    [--base-url URL | env AMPLIFY_API_BASE_URL] \
    [--mode all|smoke|assistants|files|embed|state] \
    [--output-dir DIR] \
    [--sample-file PATH] \
    [--model-id ID] \
    [--data-sources JSON_ARRAY] \
    [--embed-data-sources JSON_ARRAY] \
    [--assistant-data-sources JSON_ARRAY] \
    [--assistant-file-keys JSON_ARRAY] \
    [--assistant-id ID] \
    [--chat-prompt STRING] \
    [--chat-question STRING] \
    [--share-target EMAIL] \
    [--state-key KEY] \
    [--destructive] \
    [--dry-run] \
    [--timeout SECONDS] \
    [--help]

Examples:
  AMPLIFY_API_TOKEN=... scripts/amplify-api-test.sh --mode smoke
  scripts/amplify-api-test.sh --token-file ~/.amplify_token --mode all --destructive
  scripts/amplify-api-test.sh --base-url https://api.example.com --mode files --sample-file ./dataset.csv
  scripts/amplify-api-test.sh --mode embed --embed-data-sources '["yourEmail@example.edu/2024-05-08/abc.json"]'

Notes:
  - Requires: curl, jq
  - By default, writes artifacts to amplify-docs/api-test-output
  - Destructive actions (deletes) are skipped unless --destructive is set
USAGE
}

log_info()  { printf "[INFO] %s\n" "$*"; }
log_warn()  { printf "[WARN] %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*" 1>&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing required command: $1"
    exit 127
  fi
}

# Load token from secrets/token.txt if available and not already set
if [[ -z "${AMPLIFY_API_TOKEN:-}" ]] && [[ -f "secrets/token.txt" ]]; then
  TOKEN=$(tr -d '\n' < "secrets/token.txt")
else
  TOKEN="${AMPLIFY_API_TOKEN:-}"
fi

# Load base URL from secrets/baseurl.txt if available and not already set
if [[ -z "${AMPLIFY_API_BASE_URL:-}" ]] && [[ -f "secrets/baseurl.txt" ]]; then
  BASE_URL=$(tr -d '\n' < "secrets/baseurl.txt")
else
  BASE_URL="${AMPLIFY_API_BASE_URL:-}"
fi
MODE="smoke"
OUTPUT_DIR="probe-results"
SAMPLE_FILE=""
MODEL_OVERRIDE=""
DATA_SOURCES_JSON=""
EMBED_DATA_SOURCES_JSON=""
ASSISTANT_DATA_SOURCES_JSON=""
ASSISTANT_FILE_KEYS_JSON=""
ASSISTANT_ID_OVERRIDE=""
CHAT_PROMPT=""
CHAT_QUESTION=""
ENABLE_CHAT_DOC=false
SHARE_TARGET=""
STATE_KEY=""
DESTRUCTIVE=false
DRY_RUN=false
TIMEOUT=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      TOKEN="$2"; shift 2 ;;
    --token-file)
      TOKEN=$(tr -d '\n' < "$2"); shift 2 ;;
    --base-url)
      BASE_URL="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --output-dir)
      OUTPUT_DIR="$2"; shift 2 ;;
    --sample-file)
      SAMPLE_FILE="$2"; shift 2 ;;
    --model-id)
      MODEL_OVERRIDE="$2"; shift 2 ;;
    --data-sources)
      DATA_SOURCES_JSON="$2"; shift 2 ;;
    --embed-data-sources)
      EMBED_DATA_SOURCES_JSON="$2"; shift 2 ;;
    --assistant-data-sources)
      ASSISTANT_DATA_SOURCES_JSON="$2"; shift 2 ;;
    --assistant-file-keys)
      ASSISTANT_FILE_KEYS_JSON="$2"; shift 2 ;;
    --assistant-id)
      ASSISTANT_ID_OVERRIDE="$2"; shift 2 ;;
    --chat-prompt)
      CHAT_PROMPT="$2"; shift 2 ;;
    --chat-question)
      CHAT_QUESTION="$2"; shift 2 ;;
    --enable-chat-doc)
      ENABLE_CHAT_DOC=true; shift ;;
    --share-target)
      SHARE_TARGET="$2"; shift 2 ;;
    --state-key)
      STATE_KEY="$2"; shift 2 ;;
    --destructive)
      DESTRUCTIVE=true; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      print_usage; exit 0 ;;
    --version)
      echo "$VERSION"; exit 0 ;;
    *)
      log_error "Unknown argument: $1"; print_usage; exit 2 ;;
  esac
done

require_cmd curl
require_cmd jq

if [[ -z "$TOKEN" ]]; then
  log_error "No token provided. Use --token/--token-file or set AMPLIFY_API_TOKEN."
  exit 2
fi

# Clean output directory before starting
if [[ -d "$OUTPUT_DIR" ]]; then
  log_info "Cleaning previous results from $OUTPUT_DIR"
  rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR/requests" "$OUTPUT_DIR/responses" "$OUTPUT_DIR/headers"

# Global state captured across steps
MODEL_ID=""
ASSISTANT_ID=""
THREAD_ID=""
RUN_ID=""
UPLOADED_FILE_KEY=""

tests_passed=0
tests_failed=0

record_result() {
  local name=$1
  local ok=$2
  if [[ "$ok" == "true" ]]; then
    tests_passed=$((tests_passed + 1))
    log_info "PASS: $name"
  else
    tests_failed=$((tests_failed + 1))
    log_error "FAIL: $name"
  fi
}

write_dry_run_response() {
  local path=$1
  local res_file=$2
  local req_file=$3
  case "$path" in
    "/available_models")
      cat > "$res_file" <<'JSON'
{ "data": [] }
JSON
      ;;
    "/chat")
      cat > "$res_file" <<'JSON'
{ "data": { "messages": [], "usage": {"inputTokens": 0, "outputTokens": 0}, "metadata": {"model": "mock", "provider": "mock" } } }
JSON
      ;;
    "/embedding-dual-retrieval")
      cat > "$res_file" <<'JSON'
{ "data": { "result": [] } }
JSON
      ;;
    "/assistant/create/codeinterpreter"|"/assistant/create")
      cat > "$res_file" <<'JSON'
{ "data": { "assistantId": "ast/mock" } }
JSON
      ;;
    "/assistant/chat/codeinterpreter")
      cat > "$res_file" <<'JSON'
{ "data": { "data": { "threadId": "thr/mock", "runId": "run/mock", "messages": [] } } }
JSON
      ;;
    "/assistant/list")
      cat > "$res_file" <<'JSON'
{ "data": { "items": [] } }
JSON
      ;;
    "/assistant/share")
      cat > "$res_file" <<'JSON'
{ "data": { "shareId": "share/mock", "recipients": [] } }
JSON
      ;;
    "/assistant/openai/delete"*)
      cat > "$res_file" <<'JSON'
{ "data": { "deleted": true } }
JSON
      ;;
    "/assistant/openai/thread/delete")
      cat > "$res_file" <<'JSON'
{ "data": { "deleted": true } }
JSON
      ;;
    "/files/query")
      cat > "$res_file" <<'JSON'
{ "data": { "items": [], "next": null } }
JSON
      ;;
    "/files/tags/list")
      cat > "$res_file" <<'JSON'
{ "data": { "tags": [] } }
JSON
      ;;
    "/files/tags/create")
      cat > "$res_file" <<'JSON'
{ "data": { "created": [] } }
JSON
      ;;
    "/files/tags/delete")
      cat > "$res_file" <<'JSON'
{ "data": { "deleted": [] } }
JSON
      ;;
    "/files/set_tags")
      # Echo back tags if present in request
      if [[ -f "$req_file" ]] && jq -e . "$req_file" >/dev/null 2>&1; then
        local tags
        tags=$(jq -c '.data.tags // []' "$req_file")
        cat > "$res_file" <<JSON
{ "data": { "fileKey": "files/mock/file.csv", "tags": ${tags} } }
JSON
      else
        cat > "$res_file" <<'JSON'
{ "data": { "fileKey": "files/mock/file.csv", "tags": [] } }
JSON
      fi
      ;;
    "/state/share/load")
      cat > "$res_file" <<'JSON'
{ "data": { "state": {} } }
JSON
      ;;
    *)
      echo "{}" > "$res_file" ;;
  esac
}

detect_mime_type() {
  local path=$1
  local mime="application/octet-stream"
  if command -v file >/dev/null 2>&1; then
    mime=$(file -b --mime-type "$path" 2>/dev/null || echo "application/octet-stream")
  else
    case "$path" in
      *.csv) mime="text/csv" ;;
      *.json) mime="application/json" ;;
      *.pdf) mime="application/pdf" ;;
      *.png) mime="image/png" ;;
      *.jpg|*.jpeg) mime="image/jpeg" ;;
      *.txt) mime="text/plain" ;;
    esac
  fi
  # Normalize CSV to text/csv even if 'file' reports text/plain
  case "$path" in
    *.csv) mime="text/csv" ;;
  esac
  echo "$mime"
}

curl_json() {
  local name=$1
  local method=$2
  local path=$3
  local body_file=$4

  local url="${BASE_URL}${path}"
  local req_file="$OUTPUT_DIR/requests/${name}.request.json"
  local res_file="$OUTPUT_DIR/responses/${name}.response.json"
  local hdr_file="$OUTPUT_DIR/headers/${name}.headers.txt"

  if [[ -n "$body_file" ]]; then
    if [[ "$body_file" != "$req_file" ]]; then
      cp "$body_file" "$req_file"
    fi
  else
    printf "{}" > "$req_file"
  fi

  local curl_cmd=(curl -sS \
    --max-time "$TIMEOUT" \
    -w "%{http_code}" \
    -D "$hdr_file" \
    -o "$res_file" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method")

  if [[ "$method" == "POST" || "$method" == "PUT" || "$method" == "PATCH" ]]; then
    curl_cmd+=(--data @"$req_file")
  fi

  curl_cmd+=("$url")

  if [[ "$DRY_RUN" == true ]]; then
    >&2 printf "DRY-RUN %s\n" "${curl_cmd[*]}"
    write_dry_run_response "$path" "$res_file" "$req_file"
    echo 200
    return 0
  fi

  local http_code
  http_code=$("${curl_cmd[@]}") || true

  # Pretty print JSON if possible
  if jq -e . >/dev/null 2>&1 < "$res_file"; then
    tmp=$(mktemp)
    jq . < "$res_file" > "$tmp" && mv "$tmp" "$res_file"
  fi

  echo "$http_code"
}

curl_multipart_upload() {
  local name=$1
  local path=$2
  local file_path=$3
  local metadata_json=$4

  local url="${BASE_URL}${path}"
  local res_file="$OUTPUT_DIR/responses/${name}.response.json"
  local hdr_file="$OUTPUT_DIR/headers/${name}.headers.txt"
  local mime
  mime=$(detect_mime_type "$file_path")
  local meta_file
  meta_file=$(mktemp)
  printf "%s" "$metadata_json" > "$meta_file"

  local curl_cmd=(curl -sS \
    --max-time "$TIMEOUT" \
    -w "%{http_code}" \
    -D "$hdr_file" \
    -o "$res_file" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${file_path};type=${mime}" \
    -F "metadata=@${meta_file};type=application/json;filename=metadata.json" \
    -X POST "$url")

  if [[ "$DRY_RUN" == true ]]; then
    >&2 printf "DRY-RUN %s\n" "${curl_cmd[*]}"
    # Minimal plausible upload response
    cat > "$res_file" <<'JSON'
{ "data": { "fileKey": "files/mock/upload.csv", "name": "upload.csv", "type": "text/csv", "tags": ["api-test"] } }
JSON
    rm -f "$meta_file"
    echo 200
    return 0
  fi

  local http_code
  http_code=$("${curl_cmd[@]}") || true
  # Try alternative encodings if the first attempt fails
  if [[ "$http_code" != "200" ]]; then
    local alt1=(curl -sS --max-time "$TIMEOUT" -w "%{http_code}" -D "$hdr_file" -o "$res_file" -H "Authorization: Bearer ${TOKEN}" -F "file=@${file_path};type=${mime}" -F "metadata=@${meta_file};type=application/json" -X POST "$url")
    http_code=$("${alt1[@]}") || true
  fi
  if [[ "$http_code" != "200" ]]; then
    local alt2=(curl -sS --max-time "$TIMEOUT" -w "%{http_code}" -D "$hdr_file" -o "$res_file" -H "Authorization: Bearer ${TOKEN}" -F "file=@${file_path};type=${mime}" -F "metadata=${metadata_json};type=application/json" -X POST "$url")
    http_code=$("${alt2[@]}") || true
  fi
  if [[ "$http_code" != "200" ]]; then
    local alt3=(curl -sS --max-time "$TIMEOUT" -w "%{http_code}" -D "$hdr_file" -o "$res_file" -H "Authorization: Bearer ${TOKEN}" -F "file=@${file_path};type=${mime}" -F "metadata=${metadata_json}" -X POST "$url")
    http_code=$("${alt3[@]}") || true
  fi

  if jq -e . >/dev/null 2>&1 < "$res_file"; then
    tmp=$(mktemp)
    jq . < "$res_file" > "$tmp" && mv "$tmp" "$res_file"
  fi

  rm -f "$meta_file"
  echo "$http_code"
}

assert_jq() {
  local file=$1
  local expr=$2
  local name=$3
  if jq -e "$expr" "$file" >/dev/null 2>&1; then
    record_result "$name" true
    return 0
  else
    log_warn "Validation failed: jq '$expr' on $file"
    record_result "$name" false
    return 1
  fi
}

# ----------------
# Test definitions
# ----------------

test_available_models() {
  local name="available_models"
  local http
  http=$(curl_json "$name" GET "/available_models" "")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  # Accept either {data: {models: []}} or {data: []}
  if jq -e '.data.models | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name .data.models array" true
    # Prefer default.id if present, else first models[].id
    MODEL_ID=$(jq -r '(.data.default.id // .data.models[0].id // "")' "$res")
  elif jq -e '.data | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name .data array" true
    MODEL_ID=$(jq -r '(.data[0].id // "")' "$res")
  else
    log_warn "available_models shape differs from spec; expected data.models[] or data[]"
    record_result "$name unexpected shape" false
    return 1
  fi
  if [[ -n "$MODEL_ID" && "$MODEL_ID" != "null" ]]; then
    log_info "Selected model id: $MODEL_ID"
  else
    log_warn "No model id found; will fallback to 'gpt-4o' for chat"
    MODEL_ID="gpt-4o"
  fi
}

test_chat() {
  local name="chat"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  local model_id
  model_id="${MODEL_OVERRIDE:-${MODEL_ID:-gpt-4o}}"
  local ds_json
  ds_json="${DATA_SOURCES_JSON:-[]}"; [[ -z "$ds_json" ]] && ds_json="[]"
  local prompt
  local question
  prompt="${CHAT_PROMPT:-What is the capital of France?}"
  question="${CHAT_QUESTION:-What is the capital of France?}"
  # Build documented chat request shape; include assistantId only if provided
  jq -nc \
    --argjson ds "$ds_json" \
    --arg model "$model_id" \
    --arg prompt "$prompt" \
    --arg question "$question" \
    --arg assistant "${ASSISTANT_ID_OVERRIDE:-}" \
    ' {data:{messages:[{role:"user", content:$question}], options:{ragOnly:false, skipRag:true, model:{id:$model}, prompt:$prompt}, temperature:0.7, max_tokens:4000, dataSources:$ds}} | (if ($assistant|length)>0 then (.data.options.assistantId=$assistant) else . end) ' \
    > "$req"
  local http
  http=$(curl_json "$name" POST "/chat" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  # If response indicates failure, surface message and fail
  if jq -e 'has("success") and (.success | type == "boolean") and (.success != true)' "$res" >/dev/null 2>&1; then
    local msg
    msg=$(jq -r '(.message // "chat failed") | (if type=="array" then join("; ") else tostring end)' "$res" 2>/dev/null || echo "chat failed")
    log_warn "chat endpoint indicated failure: ${msg}"
    record_result "$name indicated failure" false
    return 1
  fi
  # Accept messages array, nested messages, or simplified success/data-string envelope
  if jq -e '.data.messages | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name messages array" true
  elif jq -e '.data.data.messages | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name nested messages array" true
  elif jq -e 'has("success") and (.success==true) and (.data | type=="string")' "$res" >/dev/null 2>&1; then
    record_result "$name string answer" true
  elif jq -e '.data | type == "string"' "$res" >/dev/null 2>&1; then
    record_result "$name string answer" true
  else
    record_result "$name response shape" false
    return 1
  fi
}

test_embedding_dual_retrieval() {
  local name="embedding-dual-retrieval"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  # Require data sources to be provided; otherwise skip test to avoid tenant-specific failures
  local ds_json
  if [[ -n "$EMBED_DATA_SOURCES_JSON" ]]; then
    ds_json="$EMBED_DATA_SOURCES_JSON"
  elif [[ -n "$DATA_SOURCES_JSON" ]]; then
    ds_json="$DATA_SOURCES_JSON"
  else
    log_warn "No embed data sources provided; skipping embedding-dual-retrieval"
    record_result "${name} skipped" true
    return 0
  fi
  cat > "$req" <<REQ
{
  "data": {
    "userInput": "Describe the policies outlined in the document.",
    "dataSources": ${ds_json},
    "limit": 3
  }
}
REQ
  local http
  http=$(curl_json "$name" POST "/embedding-dual-retrieval" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.result | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name result array" true
  elif jq -e '.result | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name result array (compat)" true
  else
    record_result "$name result array" false
  fi
}

test_assistant_create() {
  local name="assistant-create"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  
  # For general assistant creation, dataSources must be full objects (not just IDs)
  # This test creates a basic assistant without data sources to avoid complexity
  cat > "$req" <<REQ
{
  "data": {
    "name": "General Assistant (API Test)",
    "description": "A general-purpose assistant for testing the /assistant/create endpoint",
    "tags": ["api-test", "general"],
    "instructions": "Respond to user queries about general knowledge topics. Be helpful and concise.",
    "disclaimer": "This assistant's responses are for informational purposes only.",
    "dataSources": [],
    "dataSourceOptions": {
      "insertAttachedDocumentsMetadata": false,
      "insertAttachedDocuments": false,
      "insertConversationDocuments": false,
      "disableDataSources": true,
      "insertConversationDocumentsMetadata": false,
      "ragConversationDocuments": false,
      "ragAttachedDocuments": false
    }
  }
}
REQ
  
  local http
  http=$(curl_json "$name" POST "/assistant/create" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.assistantId | type == "string"' "$res" >/dev/null 2>&1; then
    record_result "$name assistantId" true
    # Capture assistant ID for potential deletion
    ASSISTANT_ID=$(jq -r '.data.assistantId' "$res")
  elif jq -e '.success == true' "$res" >/dev/null 2>&1; then
    record_result "$name success" true
  else
    record_result "$name response shape" false
    return 1
  fi
}

test_assistant_create_codeinterpreter() {
  local name="assistant-create-codeinterpreter"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  local ds_json
  local fk_json
  ds_json="${ASSISTANT_DATA_SOURCES_JSON:-[]}"; [[ -z "$ds_json" ]] && ds_json="[]"
  fk_json="${ASSISTANT_FILE_KEYS_JSON:-[]}"; [[ -z "$fk_json" ]] && fk_json="[]"
  local req_json
  req_json=$(jq -nc \
    --arg name "Code Interpreter Assistant (CI Test)" \
    --arg desc "Creates charts from uploaded CSVs and performs simple analysis." \
    --arg instr "Use uploaded files to run analysis and produce charts." \
    --argjson tags '["api-test"]' \
    --argjson ds ${ds_json:-null} \
    --argjson fk ${fk_json:-null} \
    ' {data:{name:$name, description:$desc, instructions:$instr, tags:$tags, tools:[{type:"code_interpreter"}]}} 
      | (if ($ds != null and ($ds|type=="array") and ($ds|length>0)) then .data.dataSources=$ds else . end)
      | (if ($fk != null and ($fk|type=="array") and ($fk|length>0)) then .data.fileKeys=$fk else . end) ')
  printf "%s" "$req_json" > "$req"
  local http
  http=$(curl_json "$name" POST "/assistant/create/codeinterpreter" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.assistantId | type == "string"' "$res" >/dev/null 2>&1; then
    record_result "$name assistantId" true
    ASSISTANT_ID=$(jq -r '.data.assistantId' "$res")
  elif jq -e '(.success == true) or (.message | type=="string")' "$res" >/dev/null 2>&1; then
    # Accept success true with no ID; continue without assistant chat
    record_result "$name success/no-id" true
    ASSISTANT_ID=""
  elif jq -e '(.success == false) and (.error | type=="string")' "$res" >/dev/null 2>&1; then
    local err
    err=$(jq -r '.error' "$res")
    log_warn "assistant create error: ${err}"
    record_result "$name error" false
    return 1
  else
    record_result "$name response shape" false
    return 1
  fi
}

test_assistant_chat_codeinterpreter() {
  if [[ -z "$ASSISTANT_ID" ]]; then
    log_warn "No ASSISTANT_ID; skipping assistant chat"
    record_result "assistant-chat-codeinterpreter skipped" true
    return 0
  fi
  # If neither assistant data sources nor file keys are provided, skip to avoid tenant-required constraints
  local ds_json
  local fk_json
  ds_json="${ASSISTANT_DATA_SOURCES_JSON:-}"
  fk_json="${ASSISTANT_FILE_KEYS_JSON:-}"
  if [[ -z "$ds_json" && -z "$fk_json" ]]; then
    log_warn "No assistant data sources or file keys; skipping assistant chat"
    record_result "assistant-chat-codeinterpreter skipped" true
    return 0
  fi
  local name="assistant-chat-codeinterpreter"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  # Default empty arrays if only one provided
  [[ -z "$ds_json" ]] && ds_json="[]"
  [[ -z "$fk_json" ]] && fk_json="[]"
  cat > "$req" <<REQ
{
  "data": {
    "assistantId": "${ASSISTANT_ID}",
    "userInput": "Say 'ok'.",
    "dataSources": ${ds_json},
    "fileKeys": ${fk_json}
  }
}
REQ
  local http
  http=$(curl_json "$name" POST "/assistant/chat/codeinterpreter" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.data.messages | type == "array"' "$name messages"
  # Capture thread/run if present
  THREAD_ID=$(jq -r '(.data.data.threadId // "")' "$res")
  RUN_ID=$(jq -r '(.data.data.runId // "")' "$res")
}

test_assistant_list() {
  local name="assistant-list"
  local http
  http=$(curl_json "$name" GET "/assistant/list" "")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.items | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name items array" true
  elif jq -e '(.success == true) and (.data | type == "array")' "$res" >/dev/null 2>&1; then
    record_result "$name data array (compat)" true
  else
    record_result "$name items array" false
  fi
}

test_assistant_share() {
  if [[ -z "$SHARE_TARGET" ]]; then
    log_warn "No --share-target provided; skipping assistant/share"
    record_result "assistant-share skipped" true
    return 0
  fi
  if [[ -z "$ASSISTANT_ID" ]]; then
    log_warn "No ASSISTANT_ID; skipping assistant/share"
    record_result "assistant-share skipped" true
    return 0
  fi
  local name="assistant-share"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  cat > "$req" <<REQ
{
  "data": {
    "assistantId": "${ASSISTANT_ID}",
    "recipientUsers": ["${SHARE_TARGET}"],
    "note": "Please review this assistant configuration."
  }
}
REQ
  local http
  http=$(curl_json "$name" POST "/assistant/share" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.recipients | type == "array"' "$name recipients array"
}

test_assistant_delete() {
  if [[ "$DESTRUCTIVE" != true ]]; then
    log_warn "--destructive not set; skipping assistant/delete"
    record_result "assistant-delete skipped" true
    return 0
  fi
  
  if [[ -z "$ASSISTANT_ID" ]]; then
    log_warn "No ASSISTANT_ID; skipping assistant/delete"
    record_result "assistant-delete skipped" true
    return 0
  fi
  
  local name="assistant-delete"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  
  cat > "$req" <<REQ
{
  "data": {
    "assistantId": "${ASSISTANT_ID}"
  }
}
REQ
  
  local http
  http=$(curl_json "$name" POST "/assistant/delete" "$req")
  
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.deleted == true' "$res" >/dev/null 2>&1; then
    record_result "$name deleted true" true
  elif jq -e '.success == true' "$res" >/dev/null 2>&1; then
    record_result "$name success" true
  else
    record_result "$name response shape" false
  fi
}

test_assistant_files_download_codeinterpreter() {
  if [[ -z "$ASSISTANT_ID" ]]; then
    log_warn "No ASSISTANT_ID; skipping assistant file download"
    record_result "assistant-files-download skipped" true
    return 0
  fi
  
  # This test requires a fileKey from assistant output
  # Could be populated from assistant chat response
  if [[ -z "${ASSISTANT_OUTPUT_FILE_KEY:-}" ]]; then
    log_warn "No assistant output file; skipping download test"
    record_result "assistant-files-download skipped" true
    return 0
  fi
  
  local name="assistant-files-download-codeinterpreter"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  
  cat > "$req" <<REQ
{
  "data": {
    "assistantId": "${ASSISTANT_ID}",
    "key": "${ASSISTANT_OUTPUT_FILE_KEY}"
  }
}
REQ
  
  local http
  http=$(curl_json "$name" POST "/assistant/files/download/codeinterpreter" "$req")
  
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  if jq -e '.data.downloadUrl | type == "string"' "$res" >/dev/null 2>&1; then
    record_result "$name downloadUrl" true
  elif jq -e '.downloadUrl | type == "string"' "$res" >/dev/null 2>&1; then
    record_result "$name downloadUrl (compat)" true
  else
    record_result "$name downloadUrl" false
  fi
}

test_assistant_delete_openai() {
  if [[ "$DESTRUCTIVE" != true ]]; then
    log_warn "--destructive not set; skipping assistant/openai/delete"
    record_result "assistant-openai-delete skipped" true
    return 0
  fi
  if [[ -z "$ASSISTANT_ID" ]]; then
    log_warn "No ASSISTANT_ID; skipping assistant/openai/delete"
    record_result "assistant-openai-delete skipped" true
    return 0
  fi
  local name="assistant-openai-delete"
  local path="/assistant/openai/delete?assistantId=$(printf '%s' "$ASSISTANT_ID" | jq -sRr @uri)"
  local http
  http=$(curl_json "$name" POST "$path" "")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.deleted == true' "$name deleted true"
}

test_assistant_thread_delete() {
  if [[ "$DESTRUCTIVE" != true ]]; then
    log_warn "--destructive not set; skipping assistant/openai/thread/delete"
    record_result "assistant-openai-thread-delete skipped" true
    return 0
  fi
  local name="assistant-openai-thread-delete"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  local thread_or_assistant
  if [[ -n "$THREAD_ID" ]]; then
    thread_or_assistant="\"threadId\": \"${THREAD_ID}\""
  elif [[ -n "$ASSISTANT_ID" ]]; then
    thread_or_assistant="\"assistantId\": \"${ASSISTANT_ID}\""
  else
    log_warn "No threadId or assistantId; skipping thread delete"
    record_result "$name skipped" true
    return 0
  fi
  cat > "$req" <<REQ
{
  "data": { ${thread_or_assistant} }
}
REQ
  local http
  http=$(curl_json "$name" POST "/assistant/openai/thread/delete" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.deleted == true' "$name deleted true"
}

test_files_upload() {
  local name="files-upload"
  local tmpfile=""
  local path_to_upload="${SAMPLE_FILE}"
  if [[ -z "$path_to_upload" || ! -f "$path_to_upload" ]]; then
    if [[ -n "$path_to_upload" && ! -f "$path_to_upload" ]]; then
      log_warn "Sample file not found at ${path_to_upload}"
    fi
    # Try to use bundled sample data
    if [[ -f "sample-data/sales-data.csv" ]]; then
      path_to_upload="sample-data/sales-data.csv"
      log_info "Using bundled sample file: ${path_to_upload}"
    else
      log_warn "No sample file provided; creating temporary CSV"
      tmpfile=$(mktemp)
      echo "col1,col2" > "$tmpfile"
      echo "1,2" >> "$tmpfile"
      echo "3,4" >> "$tmpfile"
      path_to_upload="$tmpfile"
    fi
  fi
  local metadata
  metadata=$(jq -nc --arg n "$(basename "$path_to_upload")" '{name:$n, tags:["analysis","api-test"], type:"text/csv"}')
  local http
  http=$(curl_multipart_upload "$name" "/files/upload" "$path_to_upload" "$metadata")
  [[ -n "$tmpfile" ]] && rm -f "$tmpfile"
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.fileKey | type == "string"' "$name fileKey"
  UPLOADED_FILE_KEY=$(jq -r '.data.fileKey' "$res")
}

test_files_query() {
  local name="files-query"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  cat > "$req" <<REQ
{
  "data": {
    "pageSize": 2,
    "forwardScan": false,
    "tags": ["api-test"]
  }
}
REQ
  local http
  http=$(curl_json "$name" POST "/files/query" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.items | type == "array"' "$name items array"
}

test_files_tags_list() {
  local name="files-tags-list"
  local http
  http=$(curl_json "$name" GET "/files/tags/list" "")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.tags | type == "array"' "$name tags array"
}

test_files_tags_create_delete() {
  local tag="ci-test-$(date +%s)"
  local name_c="files-tags-create"
  local req_c="$OUTPUT_DIR/requests/${name_c}.request.json"
  cat > "$req_c" <<REQ
{
  "data": { "tags": ["${tag}"] }
}
REQ
  local http
  http=$(curl_json "$name_c" POST "/files/tags/create" "$req_c")
  if [[ "$http" != "200" ]]; then
    record_result "$name_c http=$http" false
  else
    local res_c="$OUTPUT_DIR/responses/${name_c}.response.json"
    if jq -e '.data.created | type == "array"' "$res_c" >/dev/null 2>&1; then
      record_result "$name_c created array" true
    elif jq -e '.success == true' "$res_c" >/dev/null 2>&1; then
      record_result "$name_c success true" true
    else
      record_result "$name_c response shape" false
    fi
  fi

  if [[ "$DESTRUCTIVE" == true ]]; then
    local name_d="files-tags-delete"
    local req_d="$OUTPUT_DIR/requests/${name_d}.request.json"
    cat > "$req_d" <<REQ
{
  "data": { "tags": ["${tag}"] }
}
REQ
    http=$(curl_json "$name_d" POST "/files/tags/delete" "$req_d")
    if [[ "$http" != "200" ]]; then
      record_result "$name_d http=$http" false
    else
      local res_d="$OUTPUT_DIR/responses/${name_d}.response.json"
      assert_jq "$res_d" '.data.deleted | type == "array"' "$name_d deleted array"
    fi
  else
    log_warn "--destructive not set; skipping files/tags/delete"
    record_result "files-tags-delete skipped" true
  fi
}

test_files_set_tags() {
  if [[ -z "$UPLOADED_FILE_KEY" ]]; then
    log_warn "No uploaded file; skipping files/set_tags"
    record_result "files-set-tags skipped" true
    return 0
  fi
  local name="files-set-tags"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  cat > "$req" <<REQ
{
  "data": {
    "fileKey": "${UPLOADED_FILE_KEY}",
    "tags": ["analysis", "api-test", "to-review"]
  }
}
REQ
  local http
  http=$(curl_json "$name" POST "/files/set_tags" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.tags | type == "array"' "$name tags array"
}

test_state_share() {
  local name="state-share"
  local http
  http=$(curl_json "$name" GET "/state/share" "")
  
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  # Validate response has items array (actual API format)
  if jq -e '.items | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name items array" true
  elif jq -e '. | type == "array"' "$res" >/dev/null 2>&1; then
    # Fallback for direct array response (PDF format)
    record_result "$name array response" true
  else
    record_result "$name response shape" false
  fi
}

test_state_share_load() {
  if [[ -z "$STATE_KEY" ]]; then
    log_warn "No --state-key provided; skipping state/share/load"
    record_result "state-share-load skipped" true
    return 0
  fi
  local name="state-share-load"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  cat > "$req" <<REQ
{
  "data": { "key": "${STATE_KEY}" }
}
REQ
  local http
  http=$(curl_json "$name" POST "/state/share/load" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  assert_jq "$res" '.data.state | type == "object"' "$name state object"
}

run_smoke() {
  log_info "Running smoke tests"
  test_available_models || true
  test_chat || true
  test_files_tags_list || true
}

run_embed() {
  log_info "Running embedding tests"
  test_embedding_dual_retrieval || true
}

run_files() {
  log_info "Running files tests"
  test_files_upload || true
  test_files_set_tags || true
  test_files_query || true
  test_files_tags_list || true
  test_files_tags_create_delete || true
}

run_state() {
  log_info "Running state management tests"
  test_state_share || true
  test_state_share_load || true
}

run_assistants() {
  log_info "Running assistants tests"
  test_assistant_create || true
  test_assistant_create_codeinterpreter || true
  test_assistant_chat_codeinterpreter || true
  test_assistant_files_download_codeinterpreter || true
  test_assistant_share || true
  test_assistant_list || true
  test_assistant_delete || true
  test_assistant_thread_delete || true
  test_assistant_delete_openai || true
}

test_chat_doc_shape() {
  local name="chat-doc"
  local req="$OUTPUT_DIR/requests/${name}.request.json"
  local ds_json
  local model_id
  local assistant_id
  local prompt
  local question
  ds_json="${DATA_SOURCES_JSON:-[]}"; [[ -z "$ds_json" ]] && ds_json="[]"
  model_id="${MODEL_OVERRIDE:-${MODEL_ID:-gpt-4o}}"
  assistant_id="${ASSISTANT_ID_OVERRIDE:-}" 
  prompt="${CHAT_PROMPT:-What is the capital of France?}"
  question="${CHAT_QUESTION:-What is the capital of France?}"

  # Build request per provided doc shape
  jq -nc \
    --argjson ds "$ds_json" \
    --arg model "$model_id" \
    --arg prompt "$prompt" \
    --arg question "$question" \
    --arg assistant "$assistant_id" \
    ' {data:{temperature:0.7, max_tokens:4000, dataSources:$ds, messages:[{role:"user", content:$question}], options:{ragOnly:false, skipRag:true, model:{id:$model}, prompt:$prompt}}} 
      | (if ($assistant|length)>0 then (.data.options.assistantId=$assistant) else . end) ' \
    > "$req"

  local http
  http=$(curl_json "$name" POST "/chat" "$req")
  if [[ "$http" != "200" ]]; then
    record_result "$name http=$http" false
    return 1
  fi
  local res="$OUTPUT_DIR/responses/${name}.response.json"
  # Accept usual messages array or surface string data
  if jq -e '.data.messages | type == "array"' "$res" >/dev/null 2>&1; then
    record_result "$name messages array" true
  elif jq -e '.data | type == "string"' "$res" >/dev/null 2>&1; then
    local detail; detail=$(jq -r '.data' "$res")
    log_warn "chat-doc returned string data: ${detail}"
    record_result "$name string data" false
  else
    record_result "$name response shape" false
  fi
}

case "$MODE" in
  smoke)
    run_smoke ;;
  embed)
    run_embed ;;
  files)
    run_files ;;
  state)
    run_state ;;
  assistants)
    run_assistants ;;
  all)
    run_smoke
    run_embed
    run_files
    run_state
    run_assistants
    if [[ "$ENABLE_CHAT_DOC" == true ]]; then test_chat_doc_shape || true; fi ;;
  *)
    log_error "Unknown mode: $MODE"; exit 2 ;;
esac

log_info "Tests passed: $tests_passed"
log_info "Tests failed: $tests_failed"

if [[ $tests_failed -gt 0 ]]; then
  exit 1
fi

exit 0


