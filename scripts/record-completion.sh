#!/usr/bin/env bash
# record-completion.sh — Hashes all request artifacts for tamper evidence
set -euo pipefail

REQUESTS_DIR="data/requests"
LOG_FILE="data/request-log.csv"

# Find the most recently completed request (status = "completed")
COMPLETED_REQUEST=""
COMPLETED_AT=""
for STATUS_FILE in "$REQUESTS_DIR"/*/status.json; do
  STATUS=$(jq -r '.status' "$STATUS_FILE")
  if [[ "$STATUS" == "completed" ]]; then
    REQ_ID=$(jq -r '.request_id' "$STATUS_FILE")
    REQ_AT=$(jq -r '.updated_at' "$STATUS_FILE")
    # Take the most recent one
    if [[ -z "$COMPLETED_AT" || "$REQ_AT" > "$COMPLETED_AT" ]]; then
      COMPLETED_REQUEST="$REQ_ID"
      COMPLETED_AT="$REQ_AT"
    fi
  fi
done

if [[ -z "$COMPLETED_REQUEST" ]]; then
  echo "ERROR: No completed request found" >&2
  exit 1
fi

echo "Recording completion for: $COMPLETED_REQUEST"

REQUEST_DIR="$REQUESTS_DIR/$COMPLETED_REQUEST"
ARTIFACTS=(
  "$REQUEST_DIR/request.json"
  "$REQUEST_DIR/classification.json"
  "$REQUEST_DIR/data-inventory.json"
  "$REQUEST_DIR/action-plan.json"
  "$REQUEST_DIR/status.json"
)

# Build hash manifest
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HASH_MANIFEST="{\"request_id\": \"$COMPLETED_REQUEST\", \"completed_at\": \"$NOW\", \"artifacts\": ["

FIRST=true
for ARTIFACT in "${ARTIFACTS[@]}"; do
  if [[ -f "$ARTIFACT" ]]; then
    HASH=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')
    FILENAME=$(basename "$ARTIFACT")
    if [[ "$FIRST" == "true" ]]; then
      FIRST=false
    else
      HASH_MANIFEST+=","
    fi
    HASH_MANIFEST+="{\"file\": \"$FILENAME\", \"sha256\": \"$HASH\"}"
  fi
done

HASH_MANIFEST+="]}"

echo "$HASH_MANIFEST" | jq '.' > "$REQUEST_DIR/completion-record.json"
echo "Wrote completion-record.json with artifact hashes"

# Update request-log.csv
if [[ -f "$LOG_FILE" ]]; then
  SUBJECT_EMAIL=$(jq -r '.subject_email' "$REQUEST_DIR/request.json")
  REQUEST_TYPE=$(jq -r '.request_type' "$REQUEST_DIR/request.json")
  SUBMITTED_DATE=$(jq -r '.submitted_date' "$REQUEST_DIR/request.json")
  # Append completion record
  echo "$COMPLETED_REQUEST,$SUBJECT_EMAIL,$REQUEST_TYPE,$SUBMITTED_DATE,completed,$NOW" >> "$LOG_FILE"
fi

# Print summary
echo ""
echo "=== Completion Record ==="
echo "Request ID:    $COMPLETED_REQUEST"
echo "Completed at:  $NOW"
echo "Artifacts hashed:"
cat "$REQUEST_DIR/completion-record.json" | jq -r '.artifacts[] | "  \(.file): \(.sha256)"'
echo "========================="
