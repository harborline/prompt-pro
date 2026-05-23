#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUG_PATH="${1:-$ROOT_DIR/.build}"
DOPPLER_PROJECT="${DOPPLER_PROJECT:-quickapp}"
DOPPLER_CONFIG="${DOPPLER_CONFIG:-dev}"

SENTRY_ORG="${PROMPT_PRODUCER_SENTRY_ORG:-}"
SENTRY_PROJECT="${PROMPT_PRODUCER_SENTRY_PROJECT:-}"
SENTRY_TOKEN="${SENTRY_AUTH_TOKEN:-${SENTRY_PERSONAL_TOKEN:-}}"

if [[ -z "$SENTRY_ORG" ]] && command -v doppler >/dev/null 2>&1; then
  SENTRY_ORG="$(doppler secrets get PROMPT_PRODUCER_SENTRY_ORG --plain --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" 2>/dev/null || true)"
fi

if [[ -z "$SENTRY_PROJECT" ]] && command -v doppler >/dev/null 2>&1; then
  SENTRY_PROJECT="$(doppler secrets get PROMPT_PRODUCER_SENTRY_PROJECT --plain --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" 2>/dev/null || true)"
fi

if [[ -z "$SENTRY_TOKEN" ]] && command -v doppler >/dev/null 2>&1; then
  SENTRY_TOKEN="$(doppler secrets get SENTRY_PERSONAL_TOKEN --plain --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" 2>/dev/null || true)"
fi

if [[ -z "$SENTRY_ORG" || -z "$SENTRY_PROJECT" || -z "$SENTRY_TOKEN" ]]; then
  echo "Missing Sentry upload configuration. Expected PROMPT_PRODUCER_SENTRY_ORG, PROMPT_PRODUCER_SENTRY_PROJECT, and SENTRY_AUTH_TOKEN or SENTRY_PERSONAL_TOKEN." >&2
  exit 1
fi

SENTRY_AUTH_TOKEN="$SENTRY_TOKEN" sentry-cli debug-files upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  "$DEBUG_PATH"
