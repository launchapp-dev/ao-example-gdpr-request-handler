#!/usr/bin/env bash
# scan-deadlines.sh — Scans all open requests and computes days remaining
set -euo pipefail

REQUESTS_DIR="data/requests"
OUTPUT_FILE="data/deadline-scan.json"

TODAY=$(date -u +"%Y-%m-%d")
echo "Scanning deadlines as of: $TODAY"

RESULTS="["
FIRST=true
COUNT=0

for STATUS_FILE in "$REQUESTS_DIR"/*/status.json; do
  [[ -f "$STATUS_FILE" ]] || continue

  STATUS=$(jq -r '.status' "$STATUS_FILE")

  # Skip completed requests
  if [[ "$STATUS" == "completed" ]]; then
    continue
  fi

  REQUEST_ID=$(jq -r '.request_id' "$STATUS_FILE")
  CREATED_AT=$(jq -r '.created_at' "$STATUS_FILE")
  CURRENT_PHASE=$(jq -r '.current_phase // "unknown"' "$STATUS_FILE")
  REQUEST_DIR=$(dirname "$STATUS_FILE")

  # Get deadline from classification if available
  DEADLINE=""
  REGULATION="gdpr"
  if [[ -f "$REQUEST_DIR/classification.json" ]]; then
    DEADLINE=$(jq -r '.deadline // empty' "$REQUEST_DIR/classification.json")
    REGULATION=$(jq -r '.regulation // "gdpr"' "$REQUEST_DIR/classification.json")
  fi

  # If no classification yet, compute from default (30 days from creation)
  if [[ -z "$DEADLINE" ]]; then
    CREATED_DATE=$(echo "$CREATED_AT" | cut -c1-10)
    if command -v gdate &>/dev/null; then
      DEADLINE=$(gdate -d "$CREATED_DATE + 30 days" +"%Y-%m-%d")
    else
      DEADLINE=$(date -v +30d -j -f "%Y-%m-%d" "$CREATED_DATE" +"%Y-%m-%d" 2>/dev/null || echo "")
    fi
    [[ -z "$DEADLINE" ]] && DEADLINE="2026-04-30"  # fallback
  fi

  # Compute days remaining
  if command -v gdate &>/dev/null; then
    TODAY_EPOCH=$(gdate -d "$TODAY" +%s)
    DEADLINE_EPOCH=$(gdate -d "$DEADLINE" +%s)
  else
    TODAY_EPOCH=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || date +%s)
    DEADLINE_EPOCH=$(date -j -f "%Y-%m-%d" "$DEADLINE" +%s 2>/dev/null || echo "$TODAY_EPOCH")
  fi

  DAYS_REMAINING=$(( (DEADLINE_EPOCH - TODAY_EPOCH) / 86400 ))
  AT_RISK="false"
  if [[ $DAYS_REMAINING -le 7 ]]; then
    AT_RISK="true"
  fi

  OVERDUE="false"
  if [[ $DAYS_REMAINING -lt 0 ]]; then
    OVERDUE="true"
  fi

  if [[ "$FIRST" == "true" ]]; then
    FIRST=false
  else
    RESULTS+=","
  fi

  RESULTS+="{\"request_id\": \"$REQUEST_ID\", \"status\": \"$STATUS\", \"current_phase\": \"$CURRENT_PHASE\", \"regulation\": \"$REGULATION\", \"deadline\": \"$DEADLINE\", \"days_remaining\": $DAYS_REMAINING, \"at_risk\": $AT_RISK, \"overdue\": $OVERDUE, \"created_at\": \"$CREATED_AT\"}"

  COUNT=$((COUNT + 1))
done

RESULTS+="]"

echo "{\"scanned_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"open_requests\": $COUNT, \"requests\": $RESULTS}" | jq '.' > "$OUTPUT_FILE"

echo "Scanned $COUNT open requests. Results written to $OUTPUT_FILE"
cat "$OUTPUT_FILE" | jq -r '.requests[] | "\(.request_id): \(.days_remaining) days remaining (at_risk: \(.at_risk))"'
