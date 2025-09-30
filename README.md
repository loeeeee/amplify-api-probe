# Amplify API Documentation

The Amplify API provides a single, authoritative interface for model discovery, conversational AI, assistant lifecycle management, file storage and tagging, retrieval-augmented search, and state sharing.

## Table of Contents

- [Quick Start](#quick-start)
- [API Reference](#api-reference)
  - [Models](#models)
  - [Chat](#chat)
  - [Retrieval](#retrieval)
  - [Assistants](#assistants)
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
- **Request envelope**: Top-level `"data"` object
- **Response envelope**: Top-level `"data"` object (some endpoints nest an additional `"data"` envelope)

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
<summary>Error Response Example</summary>

```json
{
  "error": {
    "code": 400,
    "message": "Bad Request"
  }
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
- `data.options.assistantId`: string
- `data.ragOnly`, `data.skipRag`: boolean
- `data.temperature`: number
- `data.max_tokens`: integer
- `data.dataSources`: array of strings

<details>
<summary>Example Request</summary>

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
<summary>Example Response</summary>

```json
{
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
- Some deployments return simplified envelope: `{"success": true, "message": "...", "data": "..."}`
- Invalid `assistantId` may return: `{"success": false, "message": "Invalid assistant id"}`
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
Create an assistant preconfigured with the code interpreter tool.

**Required Fields**:
- `data.name`: string
- `data.instructions`: string

**Optional Fields**: Same as `/assistant/create`

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "name": "Code Interpreter Assistant",
    "instructions": "Use uploaded files to run analysis and produce charts.",
    "tools": [{ "type": "code_interpreter" }]
  }
}
```

**Response**:
```json
{
  "data": {
    "message": "Assistant with code interpreter created successfully.",
    "assistantId": "ast/ci-20240508-xyz789"
  }
}
```
</details>

#### POST /assistant/chat/codeinterpreter
Send a message to a code interpreter assistant.

**Required Fields**:
- `data.assistantId`: string
- `data.userInput`: string

**Optional Fields**:
- `data.dataSources`: array of strings
- `data.fileKeys`: array of strings

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "assistantId": "ast/ci-20240508-xyz789",
    "userInput": "Load the CSV and compute summary statistics.",
    "fileKeys": ["files/20240508/dataset.csv"]
  }
}
```

**Response** (note nested `data.data`):
```json
{
  "data": {
    "data": {
      "threadId": "thr/20240508/123456",
      "runId": "run/20240508/abcdef",
      "messages": [
        {
          "role": "assistant",
          "content": "I loaded the file and computed mean, median, and standard deviation."
        }
      ]
    }
  }
}
```
</details>

#### POST /assistant/files/download/codeinterpreter
Retrieve a presigned URL to download a file produced by the code interpreter.

**Required Fields**:
- `data.assistantId`: string
- `data.fileKey`: string

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "assistantId": "ast/ci-20240508-xyz789",
    "fileKey": "outputs/plots/summary.png"
  }
}
```

**Response**:
```json
{
  "data": {
    "downloadUrl": "YOUR_BASE_URL/downloads/presigned/outputs/plots/summary.png?sig=..."
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
<summary>Example Response</summary>

```json
{
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

#### POST /assistant/openai/delete
Delete an assistant (OpenAI-backed).

**Query Parameter**:
- `assistantId`: string

**Request**: No body required; pass `assistantId` in query string.

**Example URL**: `YOUR_BASE_URL/assistant/openai/delete?assistantId=ast/ci-20240508-xyz789`

<details>
<summary>Example Response</summary>

```json
{
  "data": {
    "deleted": true
  }
}
```
</details>

#### POST /assistant/openai/thread/delete
Delete a thread associated with an assistant.

**Required Fields** (one of):
- `data.assistantId`: string
- `data.threadId`: string

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "threadId": "thr/20240508/123456"
  }
}
```

**Response**:
```json
{
  "data": {
    "deleted": true
  }
}
```
</details>

---

### Files

#### POST /files/upload
Upload a file with optional metadata and actions.

**Content-Type**: `multipart/form-data`

**Form Fields**:
- `file`: binary (required)
- `metadata`: JSON string (optional)
- `actions`: JSON string (optional)

<details>
<summary>curl Example</summary>

```bash
curl -s -X POST "YOUR_BASE_URL/files/upload" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@./dataset.csv;type=text/csv" \
  -F "metadata={\"name\":\"dataset.csv\",\"tags\":[\"analysis\"],\"type\":\"text/csv\"};type=application/json"
```
</details>

<details>
<summary>Example Response</summary>

```json
{
  "data": {
    "fileKey": "files/20240508/report.pdf",
    "name": "report.pdf",
    "type": "application/pdf",
    "tags": ["reports"]
  }
}
```
</details>

**Notes**:
- Multipart `metadata` is most compatible when sent with `type=application/json`
- Setting the file part MIME type improves gateway compatibility

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
    "next": {
      "pageKey": {
        "id": "files/20240508/report.pdf",
        "createdAt": "2024-05-08T14:30:00Z",
        "type": "application/pdf"
      }
    }
  }
}
```
</details>

#### GET /files/tags/list
List all existing tags.

**Request**: No body required.

<details>
<summary>Example Response</summary>

```json
{
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
  "data": {
    "created": ["to-review", "experiments"]
  }
}
```
</details>

#### POST /files/tags/delete
Delete tags.

**Required Fields**:
- `data.tags`: array of strings

<details>
<summary>Example Request/Response</summary>

**Request**:
```json
{
  "data": {
    "tags": ["raw"]
  }
}
```

**Response**:
```json
{
  "data": {
    "deleted": ["raw"]
  }
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

#### POST /state/share/load
Load a shared state using a composite key.

**Required Fields**:
- `data.key`: string (format: `"YOUR_EMAIL/SHARED_BY_EMAIL/id.json"`)

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

### Scenario A: Code Interpreter Assistant Workflow

Complete workflow for creating a code interpreter assistant, uploading files, chatting, and downloading results.

<details>
<summary>Step-by-Step Example</summary>

**1. Create Assistant**
```json
{
  "data": {
    "name": "CI Data Assistant",
    "instructions": "Analyze uploaded CSVs and produce statistical summaries.",
    "tools": [{ "type": "code_interpreter" }]
  }
}
```

**2. Upload File**
```bash
curl -s -X POST "YOUR_BASE_URL/files/upload" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@./sales.csv;type=text/csv" \
  -F "metadata={\"name\":\"sales.csv\",\"tags\":[\"analysis\"],\"type\":\"text/csv\"}"
```

**3. Chat with Assistant**
```json
{
  "data": {
    "assistantId": "ast/ci-20240508-xyz789",
    "userInput": "Load sales.csv and compute summary statistics.",
    "fileKeys": ["files/20240508/sales.csv"]
  }
}
```

**4. Download Output**
```json
{
  "data": {
    "assistantId": "ast/ci-20240508-xyz789",
    "fileKey": "outputs/sales-summary.csv"
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

### Scenario C: Dual-Retrieval Search with File Tagging

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

- **Model Options**: Always pass `options.model` as an object with an `id` field, not as a string or array
- **RAG Behavior**: Set `skipRag: false` (default) and provide `dataSources` to enable retrieval-augmented generation
- **Code Interpreter**: Responses use nested envelopes: `{"data":{"data":{...}}}`
- **Compatibility**: Some endpoints may return simplified envelopes depending on deployment
- **JSON Formatting**: All examples use valid JSON with straight quotes

---

## License

See [LICENSE](LICENSE) file for details.
