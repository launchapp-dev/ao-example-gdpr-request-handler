# GDPR Data Subject Request Handler — Agent Context

This repository implements an automated GDPR/CCPA Data Subject Request (DSR) pipeline.
You are working in a legally sensitive compliance context. Accuracy and completeness matter —
errors here can result in regulatory fines of up to 4% of annual global revenue.

## What This Pipeline Does

Processes four types of Data Subject Requests under GDPR/CCPA:
1. **Access (Art. 15)** — Subject wants to see all data held about them
2. **Erasure (Art. 17)** — Subject wants their data deleted ("right to be forgotten")
3. **Portability (Art. 20)** — Subject wants a machine-readable export
4. **Rectification (Art. 16)** — Subject wants inaccurate data corrected

## File Layout

```
data/incoming/          ← New request JSON files land here
data/requests/          ← One directory per request, created by validate-request.sh
  {request-id}/
    request.json        ← Original request + assigned ID
    classification.json ← Type, deadline, complexity, identity status
    data-inventory.json ← All personal data found per source
    action-plan.json    ← Steps to fulfill the request
    status.json         ← Current processing status
    completion-record.json ← SHA-256 hashes of all artifacts (written last)

output/audit-trails/    ← Formal compliance audit documents
output/response-letters/ ← Finalized letters to data subjects
output/alerts/          ← Deadline warning files
data/request-log.csv    ← Running log: all requests ever processed
data/deadline-scan.json ← Written by scan-deadlines.sh, read by assess-risk phase
data/deadline-assessment.json ← Written by assess-risk phase, read by generate-alerts.sh
data/weekly-metrics.json ← Written by aggregate-metrics.sh, read by generate-dashboard phase
```

## Status Flow

```
validated → classified → data-located → plan-generated → completed
```

Always update `status.json` when transitioning between phases. Include `updated_at` timestamp.

## Request ID Format

`DSR-{YYYYMMDD}-{first8ofSHA256(email)}`

Example: `DSR-20260331-a1b2c3d4`

This is computed by `validate-request.sh` — do not change the format.

## Key Configuration Files

- `config/org-config.yaml` — Organization info, DPO contact, regulation defaults
- `config/data-sources.yaml` — ALL systems containing personal data (search these all)
- `config/data-categories.yaml` — GDPR personal data category definitions
- `config/response-templates.yaml` — Letter templates by request type

## Critical Legal Rules

1. **Never skip data sources** — missing a source invalidates the erasure/access response
2. **Document ALL exceptions** — data retained under Art. 17(3) must have explicit legal basis
3. **Tamper-evident records** — completion-record.json hashes must be accurate
4. **Deadline is hard** — 30 days GDPR, 45 days CCPA. No grace period.
5. **Identity verification** — for erasure requests, do not proceed if identity is unverified
6. **Third-party notification** — erasure must include notifying downstream processors (Art. 19)

## MCP Servers Available

- **filesystem** — read/write all files in this project
- **memory** — persistent knowledge graph for cross-request subject data location registry
- **sequential-thinking** — use for erasure dependency ordering and complex legal reasoning

## Useful CLI Commands

```bash
# Find all open requests
for f in data/requests/*/status.json; do
  status=$(jq -r '.status' "$f"); req=$(jq -r '.request_id' "$f")
  echo "$req: $status"
done

# Check for at-risk requests
cat data/deadline-assessment.json | jq '.requests[] | select(.category == "at-risk")'

# View audit trail for a specific request
cat output/audit-trails/DSR-20260331-a1b2c3d4-audit.md
```

## Data Subject Privacy

The personal data in `data/sample-data/` is fictional demo data. In production:
- Never log personal data to stdout
- Never include personal data in git commits
- Audit trail documents in `output/` should be treated as sensitive records
- Access to this pipeline should be restricted to authorized compliance personnel
