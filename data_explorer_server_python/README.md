## Data Explorer MCP Server

This FastMCP server backs the Data Explorer demo widget. It accepts CSV uploads, profiles column metadata, serves preview rows with optional filters, and produces chart-ready aggregates.

### Prerequisites

- Python 3.10 or later
- `uv` (recommended) or `pip`
- Frontend assets built via `pnpm run build` (the server loads `assets/data-explorer-*.html`)

### Setup

```bash
cd data_explorer_server_python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Run

```bash
uvicorn data_explorer_server_python.main:app --port 8001 --reload
```

Once built, the server serves the widget's HTML, JS, and CSS directly over MCP resource requests,
so you don't need to run a separate static asset host. Re-run `pnpm run build` whenever you update
the frontend code to refresh the embedded assets.

Interactive tooling (ChatGPT Apps SDK, `mcp-client`, etc.) can then call the following tools:

- `data-explorer.open` – returns the widget template and recent dataset summaries.
- `data-explorer.uploadInit` – begin a chunked upload session for large CSVs (returns an `uploadId`).
- `data-explorer.uploadChunk` – append CSV text to a session; mark the final chunk with `isFinal=true` to trigger profiling.
- `data-explorer.upload` – store and profile an uploaded CSV. Supply either `csvText` (inline
  string data) or a `filePath`/`fileUri` pointing to a local file when the dataset is already on
  disk.
- `data-explorer.preview` – fetch filtered table rows with pagination.
- `data-explorer.chart` – build datasets for bar, scatter, or histogram charts.

Restart the server to clear in-memory datasets.
