#!/usr/bin/env bash
# generate-alerts.sh — Writes alert files for at-risk and overdue requests
set -euo pipefail

ASSESSMENT_FILE="data/deadline-assessment.json"
ALERTS_DIR="output/alerts"
REQUESTS_DIR="data/requests"

mkdir -p "$ALERTS_DIR"

if [[ ! -f "$ASSESSMENT_FILE" ]]; then
  echo "ERROR: $ASSESSMENT_FILE not found. Run assess-risk phase first." >&2
  exit 1
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date -u +"%Y-%m-%d")

OVERDUE_COUNT=0
AT_RISK_COUNT=0

# Process overdue requests
while IFS= read -r REQUEST; do
  REQUEST_ID=$(echo "$REQUEST" | jq -r '.request_id')
  DEADLINE=$(echo "$REQUEST" | jq -r '.deadline')
  DAYS=$(echo "$REQUEST" | jq -r '.days_remaining')
  ESCALATION=$(echo "$REQUEST" | jq -r '.escalation_notes // "No escalation notes available"')
  SUBJECT_EMAIL=$(jq -r '.subject_email // "unknown"' "$REQUESTS_DIR/$REQUEST_ID/request.json" 2>/dev/null || echo "unknown")
  REQUEST_TYPE=$(jq -r '.request_type // "unknown"' "$REQUESTS_DIR/$REQUEST_ID/request.json" 2>/dev/null || echo "unknown")

  ALERT_FILE="$ALERTS_DIR/overdue-${REQUEST_ID}.md"
  cat > "$ALERT_FILE" <<EOF
# OVERDUE ALERT: $REQUEST_ID

**Generated:** $NOW
**Status:** OVERDUE — regulatory deadline has passed

## Request Details
- **Request ID:** $REQUEST_ID
- **Subject Email:** $SUBJECT_EMAIL
- **Request Type:** $REQUEST_TYPE (${REQUEST_TYPE^^})
- **Regulatory Deadline:** $DEADLINE
- **Days Overdue:** $(echo "$DAYS * -1" | bc) days

## Required Immediate Actions
$ESCALATION

## Regulatory Risk
This request has exceeded its regulatory deadline. Under GDPR Article 12(3), failure to
respond within the statutory period may result in complaints to supervisory authorities
and fines of up to €20 million or 4% of annual global turnover (whichever is higher).

## Next Steps
1. Notify DPO immediately (dpo@example.com)
2. Contact legal team for guidance on late response
3. Expedite processing of this request as highest priority
4. Document reason for delay in audit trail
5. Consider proactive communication to the data subject with apology and timeline
EOF

  echo "OVERDUE alert written: $ALERT_FILE"
  OVERDUE_COUNT=$((OVERDUE_COUNT + 1))
done < <(jq -c '.requests[] | select(.category == "overdue")' "$ASSESSMENT_FILE" 2>/dev/null || true)

# Process at-risk requests
while IFS= read -r REQUEST; do
  REQUEST_ID=$(echo "$REQUEST" | jq -r '.request_id')
  DEADLINE=$(echo "$REQUEST" | jq -r '.deadline')
  DAYS=$(echo "$REQUEST" | jq -r '.days_remaining')
  ESCALATION=$(echo "$REQUEST" | jq -r '.escalation_notes // "Monitor closely and expedite processing"')
  SUBJECT_EMAIL=$(jq -r '.subject_email // "unknown"' "$REQUESTS_DIR/$REQUEST_ID/request.json" 2>/dev/null || echo "unknown")

  ALERT_FILE="$ALERTS_DIR/at-risk-${REQUEST_ID}.md"
  cat > "$ALERT_FILE" <<EOF
# AT-RISK WARNING: $REQUEST_ID

**Generated:** $NOW
**Status:** AT-RISK — $DAYS days until regulatory deadline

## Request Details
- **Request ID:** $REQUEST_ID
- **Subject Email:** $SUBJECT_EMAIL
- **Regulatory Deadline:** $DEADLINE
- **Days Remaining:** $DAYS

## Recommended Actions
$ESCALATION

## Extension Option
If this request qualifies as "complex" and the deadline has not yet passed, a one-time
extension of up to 60 additional days may be applied (GDPR Article 12(3)). This requires:
1. Notifying the data subject within the original deadline period
2. Explaining the reasons for the extension
3. DPO approval and documentation

Contact dpo@example.com to initiate an extension if warranted.
EOF

  echo "AT-RISK alert written: $ALERT_FILE"
  AT_RISK_COUNT=$((AT_RISK_COUNT + 1))
done < <(jq -c '.requests[] | select(.category == "at-risk")' "$ASSESSMENT_FILE" 2>/dev/null || true)

echo ""
echo "=== Alert Summary ==="
echo "Overdue requests:  $OVERDUE_COUNT"
echo "At-risk requests:  $AT_RISK_COUNT"
echo "Alert files in:    $ALERTS_DIR/"
echo "===================="
