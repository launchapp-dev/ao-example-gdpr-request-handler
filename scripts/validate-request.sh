#!/usr/bin/env bash
# validate-request.sh — Validates incoming DSR JSON and creates request directory
set -euo pipefail

INCOMING_DIR="data/incoming"
REQUESTS_DIR="data/requests"
LOG_FILE="data/request-log.csv"

# Find the newest unprocessed request file
NEWEST_FILE=$(ls -t "$INCOMING_DIR"/*.json 2>/dev/null | head -1 || true)

if [[ -z "$NEWEST_FILE" ]]; then
  echo "ERROR: No request files found in $INCOMING_DIR" >&2
  exit 1
fi

echo "Processing request file: $NEWEST_FILE"

# Validate required fields using jq
for field in subject_name subject_email request_type submitted_date; do
  VALUE=$(jq -r ".$field // empty" "$NEWEST_FILE")
  if [[ -z "$VALUE" ]]; then
    echo "ERROR: Missing required field: $field" >&2
    exit 1
  fi
done

# Validate request_type
REQUEST_TYPE=$(jq -r '.request_type' "$NEWEST_FILE")
if [[ ! "$REQUEST_TYPE" =~ ^(access|erasure|portability|rectification)$ ]]; then
  echo "ERROR: Invalid request_type '$REQUEST_TYPE'. Must be: access, erasure, portability, or rectification" >&2
  exit 1
fi

# Compute request ID: DSR-{date}-{first 8 chars of sha256 of email}
SUBJECT_EMAIL=$(jq -r '.subject_email' "$NEWEST_FILE")
SUBMITTED_DATE=$(jq -r '.submitted_date' "$NEWEST_FILE")
DATE_PART=$(echo "$SUBMITTED_DATE" | tr -d '-')
EMAIL_HASH=$(echo -n "$SUBJECT_EMAIL" | shasum -a 256 | cut -c1-8)
REQUEST_ID="DSR-${DATE_PART}-${EMAIL_HASH}"

echo "Assigned Request ID: $REQUEST_ID"

# Create request directory
REQUEST_DIR="$REQUESTS_DIR/$REQUEST_ID"
mkdir -p "$REQUEST_DIR"

# Copy validated request with ID injected
jq --arg id "$REQUEST_ID" '. + {request_id: $id}' "$NEWEST_FILE" > "$REQUEST_DIR/request.json"

# Write initial status
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$REQUEST_DIR/status.json" <<EOF
{
  "request_id": "$REQUEST_ID",
  "status": "validated",
  "created_at": "$NOW",
  "updated_at": "$NOW",
  "current_phase": "classify-request"
}
EOF

# Initialize request-log.csv if needed
if [[ ! -f "$LOG_FILE" ]]; then
  echo "request_id,subject_email,request_type,submitted_date,status,created_at" > "$LOG_FILE"
fi

# Append to log
echo "$REQUEST_ID,$SUBJECT_EMAIL,$REQUEST_TYPE,$SUBMITTED_DATE,validated,$NOW" >> "$LOG_FILE"

# Move processed file to avoid re-processing
mv "$NEWEST_FILE" "${NEWEST_FILE%.json}.processed"

echo "Request $REQUEST_ID validated and staged at $REQUEST_DIR"
