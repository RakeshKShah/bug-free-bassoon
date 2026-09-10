#!/usr/bin/env bash
set -euo pipefail

# Shared infra setup for task_6954783313_20260910032107 API tests
# This script is sourced by case-specific test scripts.

# Database URL via toxiproxy, matching .codevalid/docker-compose.yml
export DATABASE_URL="postgresql://app:app@toxiproxy:5432/appdb"

# App port as configured in .codevalid/docker-compose.yml and src/index.ts
export PORT="6713"

# Ensure required CLI tools are available (psql, curl, jq)
command -v psql >/dev/null 2>&1 || { echo "psql is required but not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required but not found"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "jq is required but not found"; exit 1; }

# JWT secret must match app configuration (see .codevalid/docker-compose.yml)
export JWT_SECRET="codevalid-test-secret"

# The seed-test container is started with app healthy; no extra wait needed here.
