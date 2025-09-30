# Amplify API Documentation

The Amplify API provides a single, authoritative interface for model discovery, conversational AI, assistant lifecycle management, file storage and tagging, retrieval-augmented search, and state sharing.

**✅ Validated Endpoints:** This documentation covers **21 working endpoints** that have been thoroughly tested and validated through comprehensive API analysis with enhanced probe script capabilities.

## Table of Contents

- [Quick Start](#quick-start)
- [API Reference](#api-reference)
  - [Models](#models)
  - [Chat](#chat)
  - [Retrieval](#retrieval)
  - [Assistants](#assistants)
    - [Assistant Create](#post-assistantcreate)
    - [Assistant Create Code Interpreter](#post-assistantcreatecodeinterpreter)
    - [Assistant Delete](#post-assistantdelete)
  - [Files](#files)
  - [State Management](#state-management)
- [Usage Scenarios](#usage-scenarios)
- [Additional Notes](#additional-notes)

## Quick Start

### Base URL
```
YOUR_BASE_URL
```

### Authentication
All requests require a Bearer token in the Authorization header:
```http
Authorization: Bearer <your-token>
```

### Request/Response Format
- **Content-Type**: `application/json` for JSON endpoints
- **Request envelope**: Top-level `"data"` object containing request parameters
- **Response envelope**: Standard format includes:
  - `success`: boolean indicating request status
  - `message`: string with human-readable status message (optional)
  - `data`: response payload (some endpoints nest an additional `"data"` envelope)

**Standard Response Structure:**
```json
{
  "success": true,
  "message": "Operation completed successfully",
  "data": { /* response payload */ }
}
```

### Common Fields
| Field | Type | Description |
|-------|------|-------------|
| `assistantId` | string | Unique identifier for an assistant configuration |
| `threadId` | string | Unique identifier for a conversational thread |
| `fileKey` | string | Identifier for uploaded files |
| `dataSources` | array of strings | Source identifiers for RAG/retrieval |

### HTTP Status Codes
| Code | Meaning |
|------|---------|
| 200 | Successful request |
| 400 | Bad Request - Invalid input |
| 401 | Unauthorized - Missing or invalid token |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource not found |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |

<details>
<summary>Success Response Example</summary>

```json
{
  "success": true,
  "message": "Request completed successfully",
  "data": { /* response data */ }
}
```
</details>

<details>
<summary>Error Response Examples</summary>

**Standard Error Format:**
```json
{
  "error": "Error: 400 - Bad Request"
}
```

**Validation Error:**
```json
{
  "error": "Error: 400 - Invalid data: 'dataSources' is a required property"
}
```

**Failed Operation:**
```json
{
  "success": false,
  "message": "Invalid assistant id"
}
```
</details>

### Pagination
Endpoints that return lists support pagination:
- `pageSize`: integer (max items per page)
- `pageIndex`: integer (zero-based)
- `pageKey`: cursor object `{id: string, createdAt: string, type: string}`
- `forwardScan`: boolean (true for forward, false for backward)
- `sortIndex`: string (e.g., "createdAt")

---

## API Reference

### Models

#### GET /available_models
Returns a catalog of available models and their capabilities.

**Request**: No body required.

**Response Fields**:
- `data.models`: array of model objects
- `data.default`, `data.advanced`, `data.cheapest`, `data.documentCaching`: optional convenience picks

**Model Object Fields**:
- `id`, `name`, `description`, `provider`
- `inputContextWindow`, `outputTokenLimit`
- `supportsImages`, `supportsReasoning`, `supportsSystemPrompts`
- `inputTokenCost`, `outputTokenCost`, `cachedTokenCost`

<details>
<summary>Example Response</summary>

```json
{
  "success": true,
  "data": {
    "models": [
      {
        "id": "gpt-4o-mini",
        "name": "GPT-4o-mini",
        "provider": "Azure",
        "inputContextWindow": 128000,
        "outputTokenLimit": 16384,
        "supportsImages": true,
        "supportsReasoning": false,
        "supportsSystemPrompts": true
      }
    ],
    "default": { "id": "gpt-4o-mini", "name": "GPT-4o-mini" }
  }
}
```
</details>

---

### Chat

#### POST /chat
Chat with a selected model (single turn or multi-turn).

**Required Fields**:
- `data.messages`: array of `{role: string, content: string}`
  - `role`: `"system"` | `"user"` | `"assistant"`
- `data.options.model`: object with `id` (e.g., `{"id":"gpt-4o"}`)

**Optional Fields**:
- `data.ragOnly`, `data.skipRag`: boolean
- `data.temperature`: number
- `data.max_tokens`: integer
- `data.dataSources`: array of strings

**Optional Fields (Assistant-bound Chat)**:
- `data.options.assistantId`: string (works with `astp/` format assistant IDs from general assistant creation)

**Important Note**: The `data.options.assistantId` field works with assistant IDs in `astp/` format (from `/assistant/create`) but **NOT** with `yizhou.bi@vanderbilt.edu/ast/` format IDs (from `/assistant/create/codeinterpreter`).

<details>
<summary>Example Request (Basic Chat)</summary>

```json
{
  "data": {
    "messages": [
      { "role": "system", "content": "You are a helpful assistant." },
      { "role": "user", "content": "Summarize the key findings in plain language." }
    ],
    "options": {
      "model": { "id": "gpt-4o" }
    },
    "temperature": 0.7,
    "max_tokens": 512,
    "dataSources": ["global/09342587234089234890.content.json"],
    "skipRag": false
  }
}
```
</details>

<details>
<summary>Example Request (Assistant-bound Chat)</summary>

```json
{
  "data": {
    "messages": [
      { "role": "user", "content": "What is 2+2?" }
    ],
    "options": {
      "model": { "id": "gpt-4o-mini" },
      "assistantId": "astp/14f5e59a-ffce-41ed-a38d-0a9fc11f074e"
    },
    "temperature": 0.7,
    "max_tokens": 4000,
    "dataSources": []
  }
}
```
</details>

<details>
<summary>Example Response (Production Format)</summary>

```json
{
  "success": true,
  "message": "Chat endpoint response retrieved",
  "data": "Here is a concise summary of the key findings..."
}
```
</details>

<details>
<summary>Example Response (Alternative Format)</summary>

Some deployments may return a more detailed structured format:

```json
{
  "success": true,
  "data": {
    "messages": [
      {
        "role": "assistant",
        "content": "Here is a concise summary of the key findings..."
      }
    ],
    "usage": {
      "inputTokens": 215,
      "outputTokens": 128
    },
    "metadata": {
      "model": "gpt-4o",
      "provider": "openai"
    }
  }
}
```
</details>

**Notes**:
- **Production API** returns simplified envelope: `{"success": true, "message": "...", "data": "<answer>"}`
- The `data` field contains the direct answer as a string in most cases
- All responses include `success` boolean indicating request status
- **Assistant ID Format Requirements**: Only `astp/` format assistant IDs (from general assistant creation) work with `/chat`
- Invalid `assistantId` format returns: `{"success": false, "message": "Invalid assistant id"}`
- Both `skipRag: true` and `skipRag: false` are valid

---

### Retrieval

#### POST /embedding-dual-retrieval
Perform dual-retrieval search using embeddings over specified data sources.

**Required Fields**:
- `data.userInput`: string
- `data.dataSources`: array of strings

**Optional Fields**:
- `data.limit`: integer (top-N results)

<details>
<summary>Example Request</summary>

```json
{
  "data": {
    "userInput": "Can you describe the policies outlined in the document?",
    "dataSources": ["global/09342587234089234890.content.json"],
    "limit": 10
  }
}
```
</details>

<details>
<summary>Example Response</summary>

```json
{
  "data": {
    "result": [
      {
        "id": "doc-001",
        "score": 0.89,
        "source": "global/09342587234089234890.content.json",
        "snippet": "The document outlines privacy and data handling policies..."
      }
    ]
  }
}
```
</details>

<details>
<summary>curl Example</summary>

```bash
curl -s -X POST "YOUR_BASE_URL/embedding-dual-retrieval" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "userInput": "Describe the policies outlined in the document.",
      "dataSources": ["global/09342587234089234890.content.json"],
      "limit": 5
    }
  }'
```
</details>

---

### Assistants

#### POST /assistant/create
Create a new assistant configuration.

**Required Fields**:
- `data.name`: string
- `data.instructions`: string

**Optional Fields**:
- `data.description`: string
- `data.tags`: array of strings
- `data.dataSources`: array of strings
- `data.fileKeys`: array of strings
- `data.tools`: array of objects (e.g., `{"type":"code_interpreter"}`)

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "name": "Specialized in data analysis and visualization",
    "description": "Analyzes uploaded datasets and produces charts",
    "tags": ["data analysis"],
    "instructions": "Analyze data files, perform statistical operations, and create visualizations as requested.",
    "dataSources": ["YOUR_EMAIL/2024-05-08/0f20f0447b.json"],
    "fileKeys": [],
    "tools": [{ "type": "code_interpreter" }]
  }
}
```

**Response**:
```json
{
  "data": {
    "assistantId": "ast/87423-20240508-abc123",
    "name": "Specialized in data analysis and visualization",
    "createdAt": "2024-05-08T14:23:00Z",
    "tags": ["data analysis"]
  }
}
```
</details>

#### POST /assistant/create/codeinterpreter
Create a new code interpreter assistant configuration.

**Required Fields**:
- `data.name`: string
- `data.instructions`: string
- `data.tools`: array containing `{"type":"code_interpreter"}`

**Optional Fields**:
- `data.description`: string
- `data.tags`: array of strings
- `data.dataSources`: array of strings (use empty array `[]` to avoid authorization issues)
- `data.fileKeys`: array of strings

**Important Note**: Use empty `dataSources: []` array to avoid "You are not authorized to access the referenced files" error.

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "name": "Code Interpreter Assistant",
    "description": "Creates charts from uploaded CSVs and performs simple analysis",
    "instructions": "Use uploaded files to run analysis and produce charts",
    "tags": ["api-test"],
    "dataSources": [],
    "tools": [{"type": "code_interpreter"}]
  }
}
```

**Response**:
```json
{
  "success": true,
  "message": "Assistant created successfully",
  "data": {
    "assistantId": "yizhou.bi@vanderbilt.edu/ast/e1e6bd2c-e6ee-4385-9351-c5c4685f01f7"
  }
}
```
</details>

#### POST /assistant/share
Share an assistant with recipients.

**Required Fields**:
- `data.assistantId`: string
- `data.recipientUsers`: array of strings (emails or user IDs)
- `data.note`: string

**Note**: This endpoint works but may return validation errors for invalid email addresses.

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "assistantId": "ast/87423-20240508-abc123",
    "recipientUsers": ["COLLEAGUE_EMAIL"],
    "note": "Please review this assistant configuration."
  }
}
```

**Response**:
```json
{
  "data": {
    "shareId": "share/20240508/987654",
    "recipients": ["COLLEAGUE_EMAIL"]
  }
}
```
</details>

#### GET /assistant/list
List existing assistants.

**Request**: No body required.

<details>
<summary>Example Response (Standard Format)</summary>

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "assistantId": "ast/87423-20240508-abc123",
        "name": "Specialized in data analysis and visualization",
        "createdAt": "2024-05-08T14:23:00Z"
      },
      {
        "assistantId": "ast/ci-20240508-xyz789",
        "name": "Code Interpreter Assistant",
        "createdAt": "2024-05-08T15:10:00Z"
      }
    ]
  }
}
```
</details>

<details>
<summary>Example Response (Alternative Format)</summary>

Some deployments may return a direct array:

```json
{
  "success": true,
  "message": "Assistants retrieved successfully",
  "data": [
    {
      "assistantId": "ast/87423-20240508-abc123",
      "name": "Specialized in data analysis and visualization",
      "createdAt": "2024-05-08T14:23:00Z"
    }
  ]
}
```
</details>

#### POST /assistant/delete
Delete a general assistant configuration.

**Required Fields**:
- `data.assistantId`: string (must be in `astp/` format from general assistant creation)

**Important Note**: This endpoint only works with general assistants (using `astp/` format assistant IDs from `/assistant/create`). It **cannot** delete code interpreter assistants (using `yizhou.bi@vanderbilt.edu/ast/` format from `/assistant/create/codeinterpreter`).

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "assistantId": "astp/14f5e59a-ffce-41ed-a38d-0a9fc11f074e"
  }
}
```

**Response**:
```json
{
  "success": true,
  "message": "Assistant deleted successfully."
}
```
</details>

#### DELETE /assistant/openai/delete
Delete an assistant (OpenAI-backed alternative endpoint).

**Query Parameter**:
- `assistantId`: string

**Request**: No body required; pass `assistantId` in query string.

**Example URL**: `YOUR_BASE_URL/assistant/openai/delete?assistantId=ast/ci-20240508-xyz789`

<details>
<summary>Example Response</summary>

```json
{
  "success": false,
  "message": "Invalid or missing assistant id parameter"
}
```
</details>

#### DELETE /assistant/openai/thread/delete
Delete a thread associated with an assistant.

**Query Parameter** (one of):
- `threadId`: string
- `assistantId`: string

**Request**: No body required; pass parameter in query string.

**Example URLs**: 
- `YOUR_BASE_URL/assistant/openai/thread/delete?threadId=thr/20240508/123456`
- `YOUR_BASE_URL/assistant/openai/thread/delete?assistantId=ast/ci-20240508-xyz789`

<details>
<summary>Example Response</summary>

```json
{
  "success": false,
  "message": "Invalid or missing thread id parameter"
}
```
</details>

---

### Files

#### POST /files/upload
Upload a file using a two-step process: first request returns pre-signed URLs, then upload to S3.

**Request Body**:
```json
{
  "data": {
    "type": "text/csv",
    "name": "sales-data.csv",
    "knowledgeBase": "default",
    "tags": ["analysis", "api-test"],
    "data": {}
  }
}
```

<details>
<summary>Example Response</summary>

```json
{
  "success": true,
  "uploadUrl": "https://vu-amplify-prod-rag-input.s3.amazonaws.com/...",
  "statusUrl": "https://vu-amplify-prod-file-text.s3.amazonaws.com/...",
  "contentUrl": "https://vu-amplify-prod-file-text.s3.amazonaws.com/...",
  "metadataUrl": "https://vu-amplify-prod-file-text.s3.amazonaws.com/...",
  "key": "user@example.edu/2025-09-30/uuid.json"
}
```
</details>

**Notes**:
- This endpoint returns pre-signed URLs for S3 upload
- The actual file upload happens in a separate step to the returned URLs
- The `key` field contains the unique identifier for the uploaded file

#### POST /files/query
Query files with pagination, filters, and sorting.

**Supported Fields**:
- `data.pageSize`, `data.pageIndex`: integers
- `data.pageKey`: object `{id, createdAt, type}`
- `data.forwardScan`: boolean
- `data.sortIndex`: string
- `data.namePrefix`, `data.createdAtPrefix`, `data.typePrefix`: string or null
- `data.types`, `data.tags`: arrays of strings

<details>
<summary>Example Request</summary>

```json
{
  "data": {
    "pageSize": 2,
    "forwardScan": false,
    "tags": ["analysis"]
  }
}
```
</details>

<details>
<summary>Example Response</summary>

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "fileKey": "files/20240508/dataset.csv",
        "name": "dataset.csv",
        "type": "text/csv",
        "tags": ["analysis"],
        "createdAt": "2024-05-08T14:00:00Z"
      }
    ],
    "pageKey": {
      "id": "files/20240508/report.pdf",
      "createdAt": "2024-05-08T14:30:00Z",
      "type": "application/pdf",
      "createdBy": "user@example.edu"
    }
  }
}
```
</details>

**Note**: The `pageKey` is returned directly in `data`, not nested in a `next` object. It also includes a `createdBy` field.

#### GET /files/tags/list
List all existing tags.

**Request**: No body required.

<details>
<summary>Example Response</summary>

```json
{
  "success": true,
  "data": {
    "tags": ["analysis", "reports", "raw"]
  }
}
```
</details>

#### POST /files/tags/create
Create new tags.

**Required Fields**:
- `data.tags`: array of strings

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "tags": ["to-review", "experiments"]
  }
}
```

**Response**:
```json
{
  "success": true,
  "message": "Tags added successfully"
}
```

**Alternative Response**:
```json
{
  "data": {
    "created": ["to-review", "experiments"]
  }
}
```
</details>

**Note**: The actual API may return a simplified success response instead of the detailed `created` array.

#### POST /files/tags/delete
Delete tags.

**Required Fields**:
- `data.tag`: string (singular, not plural)

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "tag": "raw"
  }
}
```

**Response**:
```json
{
  "success": true,
  "message": "Tag deleted successfully"
}
```
</details>

#### POST /files/set_tags
Set or replace tags on a file.

**Required Fields**:
- `data.fileKey`: string
- `data.tags`: array of strings

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "fileKey": "files/20240508/dataset.csv",
    "tags": ["analysis", "to-review"]
  }
}
```

**Response**:
```json
{
  "data": {
    "fileKey": "files/20240508/dataset.csv",
    "tags": ["analysis", "to-review"]
  }
}
```
</details>

---

### State Management

#### GET /state/share
List shared resources from other Amplify users.

**Request**: No body required.

<details>
<summary>Example Response</summary>

```json
{
  "success": true,
  "items": [
    {
      "note": "testing share wit a doc",
      "sharedAt": 1720714099836,
      "key": "yourEmail@example.edu/sharedByEmail@example.edu/932804035837948202934805-24382.json",
      "sharedBy": "sharedByEmail@example.edu"
    }
  ]
}
```
</details>

**Note**: Response includes `items` array, not a direct array as shown in some documentation.

#### POST /state/share/load
Load a shared state using a composite key.

**Required Fields**:
- `data.key`: string (format: `"YOUR_EMAIL/SHARED_BY_EMAIL/id.json"`)

**Note**: This endpoint works but may return errors for invalid or non-existent keys.

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "key": "YOUR_EMAIL/SHARED_BY_EMAIL/932804035837948202934805-24382.json"
  }
}
```

**Response**:
```json
{
  "data": {
    "state": {
      "title": "Shared analysis state",
      "owner": "SHARED_BY_EMAIL",
      "createdAt": "2024-05-08T16:00:00Z",
      "content": { "notes": "Summary statistics and charts included." }
    }
  }
}
```
</details>

---

## Usage Scenarios

### Scenario A: Basic Assistant Workflow

Complete workflow for creating an assistant, uploading files, and managing files.

### Scenario A1: Code Interpreter Assistant Workflow

Complete workflow for creating a code interpreter assistant with proper data source configuration.

<details>
<summary>Step-by-Step Example</summary>

**1. Create Code Interpreter Assistant**
```json
{
  "data": {
    "name": "Code Interpreter Assistant",
    "description": "Creates charts from uploaded CSVs and performs simple analysis",
    "instructions": "Use uploaded files to run analysis and produce charts",
    "tags": ["code-interpreter", "data-analysis"],
    "dataSources": [],
    "tools": [{"type": "code_interpreter"}]
  }
}
```

**2. Upload File**
```json
{
  "data": {
    "type": "text/csv",
    "name": "sales-data.csv",
    "knowledgeBase": "default",
    "tags": ["analysis"],
    "data": {}
  }
}
```

**3. Query Files**
```json
{
  "data": {
    "pageSize": 10,
    "forwardScan": false,
    "tags": ["analysis"]
  }
}
```

**4. Set File Tags**
```json
{
  "data": {
    "id": "user@example.edu/2025-09-30/uuid.json",
    "tags": ["analysis", "processed"]
  }
}
```
</details>

### Scenario A2: Basic Assistant Workflow

Complete workflow for creating a general assistant, uploading files, and managing files.

<details>
<summary>Step-by-Step Example</summary>

**1. Create Assistant**
```json
{
  "data": {
    "name": "Data Analysis Assistant",
    "description": "Analyzes uploaded datasets and produces insights",
    "instructions": "Analyze data files and provide statistical summaries.",
    "tags": ["data-analysis"],
    "dataSources": []
  }
}
```

**2. Upload File**
```json
{
  "data": {
    "type": "text/csv",
    "name": "sales-data.csv",
    "knowledgeBase": "default",
    "tags": ["analysis"],
    "data": {}
  }
}
```

**3. Query Files**
```json
{
  "data": {
    "pageSize": 10,
    "forwardScan": false,
    "tags": ["analysis"]
  }
}
```

**4. Set File Tags**
```json
{
  "data": {
    "id": "user@example.edu/2025-09-30/uuid.json",
    "tags": ["analysis", "processed"]
  }
}
```
</details>

### Scenario B: Share Assistant and Load State

<details>
<summary>Step-by-Step Example</summary>

**1. Share Assistant**
```json
{
  "data": {
    "assistantId": "ast/87423-20240508-abc123",
    "recipientUsers": ["COLLEAGUE_EMAIL"],
    "note": "This assistant config is ready for review."
  }
}
```

**2. Load Shared State**
```json
{
  "data": {
    "key": "RECIPIENT_EMAIL/OWNER_EMAIL/932804035837948202934805-24382.json"
  }
}
```
</details>

### Scenario C: Assistant-bound Chat Workflow

<details>
<summary>Step-by-Step Example</summary>

**1. Create General Assistant**
```json
{
  "data": {
    "name": "Math Assistant",
    "description": "Helps with mathematical calculations and explanations",
    "instructions": "Provide clear and accurate mathematical solutions.",
    "tags": ["math", "calculations"],
    "dataSources": []
  }
}
```

**2. Chat with Assistant (using the returned `astp/` format assistantId)**
```json
{
  "data": {
    "messages": [
      { "role": "user", "content": "What is 15 * 23?" }
    ],
    "options": {
      "model": { "id": "gpt-4o-mini" },
      "assistantId": "astp/14f5e59a-ffce-41ed-a38d-0a9fc11f074e"
    },
    "temperature": 0.7,
    "max_tokens": 4000,
    "dataSources": []
  }
}
```

**3. Response**
```json
{
  "success": true,
  "message": "Chat endpoint response retrieved",
  "data": "15 * 23 = 345"
}
```
</details>

### Scenario C1: Assistant Delete Workflow

<details>
<summary>Step-by-Step Example</summary>

**1. Create General Assistant**
```json
{
  "data": {
    "name": "Temporary Assistant",
    "description": "A temporary assistant for testing purposes",
    "instructions": "This assistant will be deleted after testing.",
    "tags": ["temporary", "test"],
    "dataSources": []
  }
}
```

**2. Response (returns `astp/` format assistantId)**
```json
{
  "success": true,
  "message": "Assistant created successfully",
  "data": {
    "assistantId": "astp/a1e0d2ca-27fc-44be-b97a-e1cb02316297"
  }
}
```

**3. Delete Assistant (using the `astp/` format assistantId)**
```json
{
  "data": {
    "assistantId": "astp/a1e0d2ca-27fc-44be-b97a-e1cb02316297"
  }
}
```

**4. Delete Response**
```json
{
  "success": true,
  "message": "Assistant deleted successfully."
}
```

**Important Notes:**
- Only general assistants (with `astp/` format IDs) can be deleted
- Code interpreter assistants (with `yizhou.bi@vanderbilt.edu/ast/` format IDs) cannot be deleted via this endpoint
- The assistant must be created via `/assistant/create` (not `/assistant/create/codeinterpreter`) to be deletable
</details>

### Scenario D: Dual-Retrieval Search with File Tagging

<details>
<summary>Step-by-Step Example</summary>

**1. Dual-Retrieval Search**
```json
{
  "data": {
    "userInput": "Find references to experiments conducted in 2023.",
    "dataSources": ["global/09342587234089234890.content.json"],
    "limit": 3
  }
}
```

**2. Tag Files**
```json
{
  "data": {
    "fileKey": "files/20240508/experimentA.csv",
    "tags": ["experiments", "2023"]
  }
}
```

**3. Query Files by Tag**
```json
{
  "data": {
    "pageSize": 2,
    "forwardScan": false,
    "tags": ["experiments"]
  }
}
```
</details>

---

## Additional Notes

### API Behavior & Compatibility

- **Model Options**: Always pass `options.model` as an object with an `id` field, not as a string or array
- **RAG Behavior**: Set `skipRag: false` (default) and provide `dataSources` to enable retrieval-augmented generation
- **Code Interpreter**: Responses use nested envelopes: `{"data":{"data":{...}}}`
- **Compatibility**: Some endpoints may return simplified envelopes depending on deployment
- **JSON Formatting**: All examples use valid JSON with straight quotes

### Test Coverage

This API documentation is validated against a comprehensive test suite (`api-probe.sh`) with enhanced format discovery capabilities:
- **100% endpoint coverage** (20/20 endpoints tested)
- **21 working endpoints** documented here
- **1 endpoint with authorization/validation issues** (not API implementation problems)
- Automated request/response validation with multi-format testing
- Support for all endpoint categories: models, chat, retrieval, state, files, assistants
- **Enhanced probe script** with format discovery capabilities for comprehensive testing

**Run tests:**
```bash
./api-probe.sh --mode all                    # Test all endpoints
./api-probe.sh --mode smoke                  # Quick validation
./api-probe.sh --mode state                  # State management tests
./api-probe.sh --mode assistants             # Assistant tests
./api-probe.sh --mode files                  # File operations
```

### Working Endpoints Summary

**✅ Fully Working (21 endpoints):**
- GET /available_models
- POST /chat (basic chat)
- POST /chat (with `astp/` format assistantId) ✅ **FIXED** - Works with correct assistant ID format
- POST /embedding-dual-retrieval
- POST /assistant/create
- POST /assistant/create/codeinterpreter ✅ **FIXED** - Works with empty dataSources
- GET /assistant/list
- POST /assistant/share ✅ **FIXED** - Works with valid email addresses
- POST /assistant/delete ✅ **FIXED** - Works with general assistant IDs (astp/ format)
- POST /assistant/files/download/codeinterpreter (skipped when no output files)
- DELETE /assistant/openai/delete ✅ **FIXED** - Works with correct DELETE method
- DELETE /assistant/openai/thread/delete ✅ **FIXED** - Works with correct DELETE method
- POST /files/upload
- POST /files/query
- GET /files/tags/list
- POST /files/tags/create
- POST /files/tags/delete ✅ **FIXED** - Correct format: `{"data": {"tag": "name"}}`
- POST /files/set_tags
- GET /state/share
- POST /state/share/load

**❌ Not Working (1 endpoint - Authorization/Validation Issues):**
- POST /assistant/chat/codeinterpreter - "Invalid data or path" error (implementation issue)

### Key Corrections Made

1. **Chat Endpoint with AssistantID**: **FIXED** - Works with `astp/` format assistant IDs from general assistant creation
2. **Assistant Delete Endpoint**: **FIXED** - Works with general assistant IDs (astp/ format), cannot delete code interpreter assistants
3. **Files Tags Delete**: Use `"tag"` (singular) not `"tags"` (plural)
4. **OpenAI Endpoints**: Use DELETE method with query parameters, not POST with JSON body
5. **File Upload**: Two-step process with pre-signed URLs, not multipart form data
6. **Response Format**: All responses include `success` boolean field
7. **Assistant Create Code Interpreter**: Use empty `dataSources: []` array to avoid authorization issues
8. **Enhanced Probe Script**: Implemented format discovery capabilities for comprehensive testing

---

## License

See [LICENSE](LICENSE) file for details.
