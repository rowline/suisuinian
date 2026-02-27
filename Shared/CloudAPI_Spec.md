# Suisuinian (碎碎念) Cloud API Specification Placeholder

The Swift Application expects a RESTful JSON API backend that routes to your custom LLMs (Gemini, DeepSeek, GPT-4o).

## Authentication
Every request must include the header:
`Authorization: Bearer <Your-Private-Key>`

## Endpoints

### 1. `POST /v1/capture/audio`
**Description:** Receives the raw `.m4a` audio file, translates/transcribes it (using Whisper, Flash models, or native ASR), caches the intent, and logs it to the Vector database.

**Request Body (JSON via NetworkManager):**
```json
{
  "timestamp": "2026-02-26T12:00:00Z",
  "base64Audio": "<BASE64_ENCODED_M4A_FILE>",
  "location": "Optional String"
}
```
*(In production, consider mapping this to a proper `multipart/form-data` upload so you aren't base64 encoding 5MB audio files.)*

**Response (200 OK):**
```json
{
  "status": "success",
  "id": "uuid-assigned-by-db"
}
```

### 2. `GET /v1/reports/daily`
**Description:** On load, the iOS app asks for today's generated report. This is where the Pro LLM pulls all entities from the VectorDB, runs reasoning on the user's stream-of-consciousness, and outputs Markdown.

**Response (200 OK):**
```json
{
  "id": "report-uuid",
  "date": "2026-02-26T00:00:00Z",
  "markdownContent": "### Today's Insights\n\nYou mentioned wanting to buy groceries and that you were stressed about the sprint planning meeting...",
  "extractedTasks": [
    {
      "id": "task-uuid-1",
      "title": "Buy Groceries",
      "isCompleted": false
    },
    {
      "id": "task-uuid-2",
      "title": "Prep for Sprint Planning",
      "isCompleted": false
    }
  ]
}
```
