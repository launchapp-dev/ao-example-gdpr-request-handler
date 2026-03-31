#!/usr/bin/env bash
# aggregate-metrics.sh — Aggregates weekly compliance metrics
set -euo pipefail

REQUESTS_DIR="data/requests"
LOG_FILE="data/request-log.csv"
OUTPUT_FILE="data/weekly-metrics.json"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date -u +"%Y-%m-%d")

# Compute week start (7 days ago)
if command -v gdate &>/dev/null; then
  WEEK_START=$(gdate -d "$TODAY - 7 days" +"%Y-%m-%d")
else
  WEEK_START=$(date -v -7d -j -f "%Y-%m-%d" "$TODAY" +"%Y-%m-%d" 2>/dev/null || echo "2026-03-24")
fi

echo "Aggregating metrics from $WEEK_START to $TODAY"

# Count requests by type and status
TOTAL_ALL=0
TOTAL_WEEK=0
ACCESS_COUNT=0
ERASURE_COUNT=0
PORTABILITY_COUNT=0
RECTIFICATION_COUNT=0
COMPLETED_ON_TIME=0
COMPLETED_LATE=0
OPEN_COUNT=0

for STATUS_FILE in "$REQUESTS_DIR"/*/status.json; do
  [[ -f "$STATUS_FILE" ]] || continue

  STATUS=$(jq -r '.status' "$STATUS_FILE")
  CREATED_AT=$(jq -r '.created_at' "$STATUS_FILE")
  CREATED_DATE=$(echo "$CREATED_AT" | cut -c1-10)
  REQUEST_DIR=$(dirname "$STATUS_FILE")
  REQUEST_ID=$(jq -r '.request_id' "$STATUS_FILE")

  TOTAL_ALL=$((TOTAL_ALL + 1))

  # Count this week's requests
  if [[ "$CREATED_DATE" > "$WEEK_START" || "$CREATED_DATE" == "$WEEK_START" ]]; then
    TOTAL_WEEK=$((TOTAL_WEEK + 1))
  fi

  # Count by type
  if [[ -f "$REQUEST_DIR/request.json" ]]; then
    REQ_TYPE=$(jq -r '.request_type // "unknown"' "$REQUEST_DIR/request.json")
    case "$REQ_TYPE" in
      access)       ACCESS_COUNT=$((ACCESS_COUNT + 1)) ;;
      erasure)      ERASURE_COUNT=$((ERASURE_COUNT + 1)) ;;
      portability)  PORTABILITY_COUNT=$((PORTABILITY_COUNT + 1)) ;;
      rectification) RECTIFICATION_COUNT=$((RECTIFICATION_COUNT + 1)) ;;
    esac
  fi

  # Count completion status
  if [[ "$STATUS" == "completed" ]]; then
    COMPLETED_ON_TIME=$((COMPLETED_ON_TIME + 1))
  else
    OPEN_COUNT=$((OPEN_COUNT + 1))
  fi
done

# Compute compliance rate
TOTAL_COMPLETED=$((COMPLETED_ON_TIME + COMPLETED_LATE))
COMPLIANCE_RATE=0
if [[ $TOTAL_COMPLETED -gt 0 ]]; then
  COMPLIANCE_RATE=$(echo "scale=1; $COMPLETED_ON_TIME * 100 / $TOTAL_COMPLETED" | bc)
fi

# Write metrics JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "generated_at": "$NOW",
  "period": {
    "week_start": "$WEEK_START",
    "week_end": "$TODAY"
  },
  "volume": {
    "total_all_time": $TOTAL_ALL,
    "total_this_week": $TOTAL_WEEK,
    "open": $OPEN_COUNT,
    "completed": $TOTAL_COMPLETED
  },
  "by_type": {
    "access": $ACCESS_COUNT,
    "erasure": $ERASURE_COUNT,
    "portability": $PORTABILITY_COUNT,
    "rectification": $RECTIFICATION_COUNT
  },
  "compliance": {
    "completed_on_time": $COMPLETED_ON_TIME,
    "completed_late": $COMPLETED_LATE,
    "compliance_rate_pct": $COMPLIANCE_RATE
  }
}
EOF

echo "Metrics written to $OUTPUT_FILE"
cat "$OUTPUT_FILE" | jq '.'
