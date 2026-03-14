# CLAUDE.md

## Project Overview

`findata-mcp` is a Rust MCP (Model Context Protocol) server that provides semantic Q&A over US company financials and macroeconomic data. It ingests SEC filings (10-K, 10-Q, 8-K), earnings transcripts, and macro indicators (unemployment, CPI, GDP) into a Qdrant vector database, enabling LLMs to answer natural-language questions about financial data via MCP tools.

**Tech stack**: Rust (2024 edition), Qdrant (vector DB), Nomic Embed v1.5 (embedding model served locally), Docker Compose.

**Repo layout**:
- `src/` — MCP server, tool handlers, ingestion pipeline, embedding client
- `src/tools/` — MCP tool implementations (`financials.rs`, `macro_indicators.rs`, `search.rs`)
- `src/ingest/` — SEC EDGAR and FRED data ingestion (`edgar.rs`, `fred.rs`, `chunker.rs`)
- `src/embed/` — Embedding client that calls the local Nomic container (`client.rs`, `batch.rs`)
- `tests/` — Integration tests (require Docker Compose services running)
- `docker/` — Dockerfiles for the MCP server and embedding service
- `docker-compose.yml` — Qdrant, Nomic Embed service, and the MCP server

## Implementation Workflow

1. Read the issue spec carefully — understand which MCP tools, ingestion sources, or API endpoints are affected
2. Create a feature branch: `git checkout -b feature/issue-<N>-<slug>`
3. Implement changes following the spec:
   - New MCP tools go in `src/tools/` and must be registered in `src/tools/mod.rs`
   - Ingestion changes go in `src/ingest/`; always handle rate limits for external APIs (EDGAR, FRED)
   - Use the `EmbedClient` from `src/embed/client.rs` for all vectorization — never call the embedding service directly
4. Run quality checks (see below)
5. Run E2E tests against Docker Compose (see below)
6. Commit with a descriptive message referencing the issue
7. Push and create a PR: `gh pr create --fill`

## Quality Checks

- **Format**: `cargo fmt --all --check`
- **Lint**: `cargo clippy --workspace --all-targets -- -D warnings`
- **Unit tests**: `cargo test --workspace`

Run all three before pushing. The CI pipeline will reject PRs that fail any of these.

## E2E Testing

1. Build all containers: `docker compose build`
2. Start services: `docker compose up -d`
3. Wait for Qdrant: `curl --retry 10 --retry-delay 3 --retry-all-errors http://localhost:6333/healthz`
4. Wait for embedding service: `curl --retry 10 --retry-delay 3 --retry-all-errors http://localhost:8090/health`
5. Wait for MCP server: `curl --retry 10 --retry-delay 3 --retry-all-errors http://localhost:3000/health`
6. Run integration tests: `cargo test --test integration -- --test-threads=1`
7. Teardown: `docker compose down -v`

## Environment

- `QDRANT_URL`: `http://localhost:6333` — Qdrant gRPC is on `localhost:6334`
- `EMBED_SERVICE_URL`: `http://localhost:8090` — local Nomic Embed v1.5 container
- `MCP_SERVER_PORT`: `3000`
- `EDGAR_USER_AGENT`: required by SEC EDGAR fair access policy (set to `findata-mcp team@example.com`)
- `FRED_API_KEY`: API key for FRED (Federal Reserve Economic Data); obtain a free key at https://fred.stlouisfed.org/docs/api/api_key.html
- `RUST_LOG`: `info` by default; set to `debug` for verbose output
- Secrets are in 1Password vault "findata-mcp Dev"

## Code Quality Scoring

Reviews are scored 1–10 in each of the following categories. A total score ≥ 50 is required for approval.

**Categories**: correctness, test coverage, error handling, performance, security, adherence to project conventions.

Severity definitions for findings:

- **CRITICAL**: Data corruption (e.g. wrong embeddings stored for a ticker), security vulnerabilities (SQL/command injection, leaked API keys), broken MCP protocol responses, panics in production code paths
- **HIGH**: Missing tests for safety-critical paths (financial data accuracy, ingestion idempotency), unhandled errors from Qdrant or external APIs, N+1 query patterns against the vector DB
- **MEDIUM**: Missing `clippy` fixes, undocumented public MCP tools, suboptimal chunking strategies, missing rate-limit handling for EDGAR/FRED
- **LOW**: Minor style issues, test naming conventions, missing edge-case tests for non-critical helpers
