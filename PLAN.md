# GDPR Data Subject Request Handler — Build Plan

## Overview

Automated pipeline for processing GDPR/CCPA data subject requests (DSRs). Handles the
full lifecycle: intake classification, personal data location across systems, data
inventory compilation, erasure/portability/rectification plan generation, regulatory
deadline tracking, and compliance audit trail production.

All data operations use filesystem MCP and CLI tools (jq, find, shasum). Memory MCP
maintains a persistent registry of known data locations and request tracking state.
Sequential-thinking MCP handles complex legal reasoning for request classification
and erasure dependency analysis.

---

## Agents (5)

| Agent | Model | Role |
|---|---|---|
| **intake-classifier** | claude-haiku-4-5 | Classifies incoming DSRs by type (access/erasure/portability/rectification), validates identity, sets regulatory deadlines |
| **data-locator** | claude-sonnet-4-6 | Searches configured data sources to find all personal data for a subject, builds comprehensive data inventory |
| **compliance-planner** | claude-sonnet-4-6 | Generates erasure plans, portability exports, or rectification instructions based on request type and data inventory |
| **deadline-tracker** | claude-haiku-4-5 | Monitors all open requests against regulatory deadlines, flags at-risk and overdue items, generates status reports |
| **audit-reporter** | claude-sonnet-4-6 | Produces formal compliance audit trails, response letters, and analytics dashboards |

### MCP Servers Used by Agents

- **filesystem** — all agents read/write JSON/markdown data files in `data/` and `output/`
- **memory** — data-locator uses for persistent data location registry; deadline-tracker uses for request state tracking
- **sequential-thinking** — intake-classifier uses for identity verification reasoning; compliance-planner uses for erasure dependency analysis

---

## Workflows (3)

### 1. `process-request` (primary — triggered per DSR)

Full request lifecycle: intake → locate data → compile inventory → generate plan → produce audit trail.

**Phases:**

1. **validate-request** (command)
   - Command: `bash scripts/validate-request.sh`
   - Reads request JSON from `data/incoming/` (newest unprocessed file)
   - Validates required fields: `subject_name`, `subject_email`, `request_type`, `submitted_date`
   - Validates `request_type` is one of: access, erasure, portability, rectification
   - Computes request ID: `DSR-{date}-{shasum of email}`
   - Copies validated request to `data/requests/{request-id}/request.json`
   - Writes `data/requests/{request-id}/status.json` with initial state
   - Exits non-zero if validation fails (missing fields, invalid type)

2. **classify-request** (agent: intake-classifier)
   - Reads `data/requests/{request-id}/request.json`
   - Determines request sub-type and scope:
     - Access: full data export vs. specific category inquiry
     - Erasure: full erasure vs. selective erasure (with legitimate interest exceptions)
     - Portability: machine-readable export format selection
     - Rectification: identifies which data fields need correction
   - Sets regulatory deadline based on jurisdiction:
     - GDPR: 30 calendar days from submission (extendable to 90 for complex)
     - CCPA: 45 calendar days (extendable to 90)
   - Flags if identity verification is needed (no verified ID attached)
   - Writes `data/requests/{request-id}/classification.json`:
     ```json
     {
       "request_id": "DSR-2026-03-31-a1b2c3",
       "request_type": "erasure",
       "sub_type": "selective",
       "regulation": "gdpr",
       "deadline": "2026-04-30",
       "complexity": "standard|complex",
       "identity_verified": true,
       "exceptions": ["legitimate_interest_billing"],
       "priority": "normal|urgent"
     }
     ```
   - Updates `data/requests/{request-id}/status.json` → "classified"
   - Uses memory MCP to check if this subject has prior requests

3. **locate-data** (agent: data-locator)
   - Reads classification from `data/requests/{request-id}/classification.json`
   - Reads data source registry from `config/data-sources.yaml`
   - For each configured data source, searches for subject's personal data:
     - Uses `find` and `grep` via filesystem to scan file-based data stores
     - Reads database inventory configs to identify table/column locations
     - Checks `config/data-sources.yaml` for system-specific search instructions
   - Uses memory MCP to recall known data locations for returning subjects
   - Builds comprehensive data inventory per source:
     ```json
     {
       "source": "user-database",
       "data_found": true,
       "categories": ["identity", "contact", "billing", "usage_logs"],
       "record_count": 47,
       "contains_sensitive": true,
       "sensitive_categories": ["payment_info"],
       "retention_policy": "3_years_post_account_closure",
       "deletion_dependencies": ["active_subscription", "pending_invoices"]
     }
     ```
   - Writes `data/requests/{request-id}/data-inventory.json`
   - Updates memory MCP with discovered data locations for this subject
   - Updates status → "data-located"

4. **review-completeness** (agent: data-locator)
   - Decision phase — reviews the data inventory for completeness
   - Checks: were all configured data sources searched? Any sources unreachable?
   - Checks: does the data inventory cover all categories listed in `config/data-categories.yaml`?
   - Decision contract:
     - `verdict`: "advance" | "rework"
     - `reasoning`: explanation of completeness assessment
     - `missing_sources`: list of sources not yet searched (if rework)
   - On rework → back to `locate-data` with notes on what to search harder
   - On advance → proceeds to plan generation

5. **generate-plan** (agent: compliance-planner)
   - Reads classification + data inventory
   - Uses sequential-thinking MCP for complex erasure dependency analysis
   - Generates action plan based on request type:
     - **Access**: compiles data export document listing all personal data by category
     - **Erasure**: generates step-by-step erasure plan with:
       - Deletion order (respecting dependencies — e.g., close subscription before deleting billing)
       - Legitimate interest exceptions (data that must be retained + legal basis)
       - Third-party notification list (processors who received the data)
       - Verification steps (how to confirm deletion is complete)
     - **Portability**: generates machine-readable export in JSON/CSV with data dictionary
     - **Rectification**: generates correction instructions per system with before/after values
   - Writes `data/requests/{request-id}/action-plan.json`
   - Writes `data/requests/{request-id}/response-letter-draft.md` (formal response to data subject)
   - Updates status → "plan-generated"

6. **generate-audit-trail** (agent: audit-reporter)
   - Reads all artifacts for the request: classification, inventory, plan
   - Produces formal compliance audit trail document:
     - Request receipt timestamp and classification
     - Data inventory summary with categories found
     - Actions taken (or planned) per data source
     - Regulatory deadline and current status
     - Exceptions applied with legal basis
     - Chain of custody for the request
   - Writes `output/audit-trails/{request-id}-audit.md`
   - Writes `output/response-letters/{request-id}-response.md` (finalized)
   - Updates status → "completed"

7. **record-completion** (command)
   - Command: `bash scripts/record-completion.sh`
   - Computes SHA-256 hash of all request artifacts for tamper evidence
   - Writes `data/requests/{request-id}/completion-record.json` with hashes
   - Appends to `data/request-log.csv` (running log of all processed requests)
   - Prints summary to stdout

**Routing:**
- `review-completeness` → on rework → `locate-data` (max 2 rework attempts)

---

### 2. `deadline-monitor` (scheduled — daily)

Checks all open requests against their regulatory deadlines.

**Phases:**

1. **scan-deadlines** (command)
   - Command: `bash scripts/scan-deadlines.sh`
   - Reads all `data/requests/*/status.json` files
   - Filters to non-completed requests
   - Computes days remaining for each against `classification.json` deadline
   - Writes `data/deadline-scan.json` with: `{request_id, status, deadline, days_remaining, at_risk}`
   - at_risk = true if ≤7 days remaining

2. **assess-risk** (agent: deadline-tracker)
   - Reads `data/deadline-scan.json`
   - Categorizes each open request:
     - **on-track**: >7 days remaining, progressing normally
     - **at-risk**: ≤7 days remaining or stalled in a phase
     - **overdue**: past deadline
     - **extension-eligible**: complex request where extension hasn't been used
   - For at-risk/overdue: generates escalation notes with recommended actions
   - Uses memory MCP to track velocity (how fast requests typically move through phases)
   - Writes `output/deadline-report.md` with traffic-light status for each request
   - Writes `data/deadline-assessment.json`

3. **generate-alerts** (command)
   - Command: `bash scripts/generate-alerts.sh`
   - Reads `data/deadline-assessment.json`
   - For overdue requests: writes `output/alerts/overdue-{request-id}.md`
   - For at-risk requests: writes `output/alerts/at-risk-{request-id}.md`
   - Prints summary counts to stdout

**Schedule:** Daily at 08:00 UTC (`0 8 * * *`)

---

### 3. `compliance-report` (scheduled — weekly)

Generates weekly compliance analytics and dashboard.

**Phases:**

1. **aggregate-metrics** (command)
   - Command: `bash scripts/aggregate-metrics.sh`
   - Reads `data/request-log.csv` and all request status files
   - Computes metrics:
     - Total requests received (this week / all time)
     - Requests by type (access/erasure/portability/rectification)
     - Average processing time by type
     - Compliance rate (% completed within deadline)
     - Open request count and age distribution
   - Writes `data/weekly-metrics.json`

2. **generate-dashboard** (agent: audit-reporter)
   - Reads `data/weekly-metrics.json` and recent audit trails
   - Produces `output/weekly-dashboard.md`:
     - Executive summary with key metrics
     - Request volume trends
     - Compliance rate tracking
     - Common data categories requested
     - Recommendations for process improvement
   - Produces `output/compliance-summary.md`:
     - Formal compliance posture document
     - Suitable for DPO review or regulatory submission
   - Uses memory MCP to compare against previous weeks' metrics

**Schedule:** Weekly on Monday at 09:00 UTC (`0 9 * * 1`)

---

## Supporting Files

### Config Files

- **`config/org-config.yaml`** — Organization details, DPO contact, jurisdiction defaults
  ```yaml
  organization:
    name: "Example Corp"
    dpo_email: "dpo@example.com"
    default_regulation: "gdpr"
    default_deadline_days: 30
    extension_allowed: true
    max_extension_days: 60
  ```

- **`config/data-sources.yaml`** — Registry of systems containing personal data
  ```yaml
  data_sources:
    - id: user-database
      type: database
      description: "Primary user accounts and profiles"
      categories: [identity, contact, preferences]
      search_instructions: "Query users table by email"
      deletion_method: "DELETE FROM users WHERE email = ?"
      has_dependencies: true
      dependencies: [billing, subscriptions]

    - id: billing-system
      type: database
      description: "Payment and invoice records"
      categories: [billing, payment_info]
      retention_required: true
      retention_basis: "legal_obligation"
      retention_period: "7_years"

    - id: application-logs
      type: filesystem
      path: "data/sample-data/logs/"
      description: "Application access and usage logs"
      categories: [usage_logs, ip_addresses]
      search_instructions: "grep for email or user ID in log files"
      deletion_method: "redact matching lines"

    - id: email-marketing
      type: third_party
      description: "Email marketing platform"
      categories: [contact, marketing_preferences]
      third_party_contact: "privacy@emailprovider.com"
      deletion_method: "API call to delete subscriber"
  ```

- **`config/data-categories.yaml`** — GDPR personal data categories
  ```yaml
  categories:
    - id: identity
      name: "Identity Data"
      examples: ["name", "username", "date of birth", "government ID"]
      sensitive: false
    - id: contact
      name: "Contact Data"
      examples: ["email", "phone", "address"]
      sensitive: false
    - id: billing
      name: "Financial Data"
      examples: ["invoices", "payment history", "account balance"]
      sensitive: false
    - id: payment_info
      name: "Payment Instruments"
      examples: ["credit card numbers", "bank accounts"]
      sensitive: true
    - id: usage_logs
      name: "Usage Data"
      examples: ["login history", "page views", "feature usage"]
      sensitive: false
    - id: ip_addresses
      name: "Technical Identifiers"
      examples: ["IP addresses", "device IDs", "cookies"]
      sensitive: false
    - id: marketing_preferences
      name: "Marketing Preferences"
      examples: ["consent records", "opt-in/out history"]
      sensitive: false
    - id: preferences
      name: "User Preferences"
      examples: ["language", "timezone", "notification settings"]
      sensitive: false
  ```

- **`config/response-templates.yaml`** — Templates for formal response letters by request type

### Scripts

- **`scripts/validate-request.sh`** — Validates incoming request JSON, assigns ID, creates request directory
- **`scripts/record-completion.sh`** — Computes artifact hashes, updates request log CSV
- **`scripts/scan-deadlines.sh`** — Scans open requests and computes days remaining
- **`scripts/generate-alerts.sh`** — Produces alert files for overdue/at-risk requests
- **`scripts/aggregate-metrics.sh`** — Aggregates weekly metrics from request log and status files

### Sample Data

- **`data/sample-data/incoming/sample-access-request.json`** — Example access request
- **`data/sample-data/incoming/sample-erasure-request.json`** — Example erasure request
- **`data/sample-data/logs/`** — Sample application logs containing mock PII for demo
- **`data/sample-data/users/`** — Sample user records for demo data location

### Output Templates

- **`templates/audit-trail.md`** — Template for compliance audit documents
- **`templates/response-letter-access.md`** — Response letter for access requests
- **`templates/response-letter-erasure.md`** — Response letter for erasure requests
- **`templates/weekly-dashboard.md`** — Weekly compliance dashboard template

---

## Directory Structure

```
examples/gdpr-request-handler/
├── .ao/workflows/
│   ├── agents.yaml
│   ├── phases.yaml
│   ├── workflows.yaml
│   ├── mcp-servers.yaml
│   └── schedules.yaml
├── config/
│   ├── org-config.yaml
│   ├── data-sources.yaml
│   ├── data-categories.yaml
│   └── response-templates.yaml
├── scripts/
│   ├── validate-request.sh
│   ├── record-completion.sh
│   ├── scan-deadlines.sh
│   ├── generate-alerts.sh
│   └── aggregate-metrics.sh
├── templates/
│   ├── audit-trail.md
│   ├── response-letter-access.md
│   ├── response-letter-erasure.md
│   └── weekly-dashboard.md
├── data/
│   ├── sample-data/
│   │   ├── incoming/
│   │   │   ├── sample-access-request.json
│   │   │   └── sample-erasure-request.json
│   │   ├── logs/
│   │   │   └── app-access.log
│   │   └── users/
│   │       ├── user-001.json
│   │       └── user-002.json
│   ├── incoming/          (drop new requests here)
│   ├── requests/          (processed request directories)
│   └── request-log.csv
├── output/
│   ├── audit-trails/
│   ├── response-letters/
│   ├── alerts/
│   ├── weekly-dashboard.md
│   └── compliance-summary.md
├── CLAUDE.md
└── README.md
```

---

## Key Design Decisions

1. **Request ID = SHA-based**: `DSR-{date}-{shasum}` ensures unique, deterministic IDs even if the same subject submits multiple requests on the same day (the full email hash disambiguates).

2. **Retention exceptions are first-class**: Erasure plans explicitly model data that CANNOT be deleted due to legal obligations (e.g., 7-year tax record retention). This is critical for GDPR compliance — Article 17(3) exceptions must be documented.

3. **Memory MCP for cross-request intelligence**: The data-locator builds up a registry of where each subject's data lives. Repeat requests (common for subjects who first request access, then erasure) are faster because data locations are already known.

4. **Tamper-evident audit trail**: SHA-256 hashes of all artifacts are recorded at completion, creating a verifiable chain for regulatory audits.

5. **Deadline tracking is a separate workflow**: Rather than embedding deadline logic into the main pipeline, a daily scheduled workflow independently monitors all open requests. This ensures nothing slips through even if the main pipeline stalls.

6. **Three-tier alert system**: on-track (no action) → at-risk (warning at 7 days) → overdue (escalation). Extension eligibility is tracked separately for complex requests.
