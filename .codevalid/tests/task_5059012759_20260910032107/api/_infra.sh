#!/usr/bin/env bash
# Shared API test infra helpers for this breakdown endpoint.
set -euo pipefail
export PORT="${PORT:-6713}"
export BASE_URL="${BASE_URL:-http://app:6713}"
export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
