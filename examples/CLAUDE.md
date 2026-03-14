# CLAUDE.md

<!-- This is a template for your project's CLAUDE.md file.
     The claude-workflows automation reads this file to understand your project's
     conventions, tooling, and testing procedures. Fill in each section below
     and delete the HTML comments when you're done. -->

## Project Overview

<!-- Brief description of what this project does, its tech stack, and architecture.
     Example:
     This is a Go + React monorepo for an internal billing service.
     Backend lives in cmd/ and pkg/, frontend in web/. -->

## Implementation Workflow

<!-- Step-by-step guide for implementing a feature from an issue.
     The implement workflows (claude-dev-loop, claude-issue-implement) follow these steps.
     Example:
     1. Read the issue spec carefully
     2. Create a feature branch: git checkout -b feature/issue-<N>-<slug>
     3. Implement the changes following the spec
     4. Run quality checks (see below)
     5. Commit with a descriptive message referencing the issue
     6. Push and create a PR -->

## Quality Checks

<!-- Commands for formatting, linting, and testing.
     The fix-iteration workflow runs these after addressing review feedback.
     Example:
     - Format: `go fmt ./...` and `cd web && npm run format`
     - Lint: `golangci-lint run` and `cd web && npm run lint`
     - Test: `go test ./...` and `cd web && npm test` -->

## E2E Testing

<!-- Build, deploy, and test procedures for end-to-end validation.
     The implement and fix workflows run these after code changes.
     Example:
     1. Build: `docker compose build`
     2. Deploy: `docker compose up -d`
     3. Wait for health: `curl --retry 10 --retry-delay 2 http://localhost:8080/health`
     4. Run e2e tests: `npm run test:e2e`
     5. Teardown: `docker compose down` -->

## Environment

<!-- Environment variables, server addresses, database details, and credentials access.
     The implement and researcher workflows reference this for deployment and testing.
     Example:
     - DATABASE_URL: postgres://localhost:5432/myapp_dev
     - API_BASE_URL: http://localhost:8080
     - Secrets are in 1Password vault "Engineering" -->

## Code Quality Scoring

<!-- Scoring rubric and categories used during code review.
     The review-iteration workflow uses this to evaluate PR quality.
     Example:
     Reviews are scored on: correctness, test coverage, error handling,
     performance, and adherence to project conventions.
     - CRITICAL: bugs, data loss, security vulnerabilities
     - HIGH: missing tests, broken error handling
     - MEDIUM: style violations, missing docs for public APIs -->
