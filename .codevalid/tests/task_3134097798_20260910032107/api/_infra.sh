#!/usr/bin/env bash
# Shared infra for API tests under task_3134097798_20260910032107
# This script is sourced by case test scripts and should not exit on its own.

set -euo pipefail

# Ensure required environment variables are present.
: "${DATABASE_URL:?DATABASE_URL must be set for tests}"

# Basic tool availability checks (non-fatal warnings where reasonable)
if ! command -v psql >/dev/null 2>&1; then
  echo "psql command not found; database operations will fail" >&2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl command not found; HTTP requests will fail" >&2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found; JSON parsing will fail" >&2
fi

# Additional seed-test helpers or common functions can be added here as needed
# while keeping behavior aligned with the test plan.
