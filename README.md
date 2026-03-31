# GDPR Data Subject Request Handler

Automated GDPR/CCPA compliance pipeline — receive, classify, locate data for, and fulfill
Data Subject Requests (DSRs) with regulatory deadline tracking and tamper-evident audit trails.

## Workflow Diagram

```
New DSR Arrives
      │
      ▼
┌─────────────────┐
│ validate-request│  (command) Validate JSON, assign DSR-{date}-{hash} ID
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│  classify-request   │  (intake-classifier) Type, deadline, identity check
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│    locate-data      │◄──────────────────────────────┐
└──────────┬──────────┘                               │ rework
           │                                          │ (max 2x)
           ▼                                    ┌─────┴───────────────┐
┌─────────────────────┐                         │ review-completeness  │
│ review-completeness │ ──── rework ──────────► │   (data-locator)     │
└──────────┬──────────┘                         └─────────────────────┘
           │ advance
           ▼
┌─────────────────────┐
│   generate-plan     │  (compliance-planner) Erasure plan / export spec / corrections
└──────────┬──────────┘
           │
           ▼
┌──────────────────────┐
│ generate-audit-trail │  (audit-reporter) Formal compliance audit + response letter
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  record-completion   │  (command) SHA-256 artifact hashes → tamper-evident record
└──────────────────────┘


SCHEDULED: Daily 08:00 UTC
────────────────────────────────────────────────────
scan-deadlines → assess-risk → generate-alerts


SCHEDULED: Weekly Monday 09:00 UTC
────────────────────────────────────────────────────
aggregate-metrics → generate-dashboard
```

## Quick Start

```bash
cd examples/gdpr-request-handler
ao daemon start

# Drop a request into the incoming directory
cp data/sample-data/incoming/sample-access-request.json data/incoming/

# Trigger the pipeline
ao queue enqueue \
  --title "gdpr-request-handler" \
  --description "Process incoming DSR" \
  --workflow-ref process-request

# Watch it process
ao daemon stream --pretty
```

## Agents

| Agent | Model | Role |
|---|---|---|
| **intake-classifier** | claude-haiku-4-5 | Classifies request type, sets GDPR/CCPA deadline, validates identity |
| **data-locator** | claude-sonnet-4-6 | Searches all data sources, builds complete data inventory per subject |
| **compliance-planner** | claude-sonnet-4-6 | Generates erasure plans, portability exports, rectification instructions |
| **deadline-tracker** | claude-haiku-4-5 | Daily monitoring of open requests — flags at-risk and overdue |
| **audit-reporter** | claude-sonnet-4-6 | Formal audit trails, response letters, weekly compliance dashboards |

## AO Features Demonstrated

| Feature | Where Used |
|---|---|
| **Scheduled workflows** | `deadline-monitor` (daily 08:00), `compliance-report` (weekly Mon 09:00) |
| **Decision contracts** | `review-completeness` — advance or rework with `missing_sources` |
| **Rework loops** | `review-completeness` → `locate-data` (max 2 attempts) |
| **Command phases** | `validate-request`, `scan-deadlines`, `record-completion`, `generate-alerts`, `aggregate-metrics` |
| **Multi-agent pipeline** | 5 specialized agents with distinct models and responsibilities |
| **Memory MCP** | Cross-request subject intelligence — repeat requests are faster |
| **Sequential-thinking MCP** | Erasure dependency ordering (cancel subscription → delete billing → delete profile) |
| **Output contracts** | Structured JSON artifacts: classification, inventory, action-plan, completion-record |
| **Multiple workflows** | `process-request` (per DSR), `deadline-monitor` (daily), `compliance-report` (weekly) |

## Request Types Supported

| Type | Regulation Article | Pipeline Output |
|---|---|---|
| **Access** | GDPR Art. 15 / CCPA §1798.100 | Data export document + response letter |
| **Erasure** | GDPR Art. 17 / CCPA §1798.105 | Ordered deletion plan + exceptions list + 3rd-party notifications |
| **Portability** | GDPR Art. 20 | Machine-readable JSON/CSV export + data dictionary |
| **Rectification** | GDPR Art. 16 | Per-system correction instructions + response letter |

## Directory Structure

```
gdpr-request-handler/
├── .ao/workflows/
│   ├── agents.yaml          # 5 agents: classifier, locator, planner, tracker, reporter
│   ├── phases.yaml          # 11 phases across 3 workflows
│   ├── workflows.yaml       # process-request, deadline-monitor, compliance-report
│   ├── mcp-servers.yaml     # filesystem, memory, sequential-thinking
│   └── schedules.yaml       # daily + weekly cron schedules
├── config/
│   ├── org-config.yaml      # Organization, DPO, regulation defaults
│   ├── data-sources.yaml    # All systems containing personal data
│   ├── data-categories.yaml # GDPR personal data categories
│   └── response-templates.yaml
├── scripts/                 # validate-request, record-completion, scan-deadlines,
│                            # generate-alerts, aggregate-metrics
├── templates/               # Audit trail, response letters, weekly dashboard
├── data/
│   ├── incoming/            # Drop new request JSON files here
│   ├── requests/            # Processed request directories (created at runtime)
│   ├── sample-data/         # Demo data: users, logs, sample requests
│   └── request-log.csv      # Running log of all processed requests
└── output/
    ├── audit-trails/        # Per-request compliance audit documents
    ├── response-letters/    # Finalized response letters to data subjects
    └── alerts/              # Deadline alert files (overdue, at-risk)
```

## Requirements

**No external API keys required** — uses only:
- `@modelcontextprotocol/server-filesystem` (file operations)
- `@modelcontextprotocol/server-memory` (cross-request subject data registry)
- `@modelcontextprotocol/server-sequential-thinking` (erasure dependency analysis)
- Standard CLI tools: `jq`, `shasum`, `bash`, `date`

**Verify prerequisites:**
```bash
which jq shasum    # should both be found
jq --version       # 1.6+
```

## Regulatory Coverage

- **GDPR** (EU/EEA): 30-day deadline, extendable to 90 for complex requests
- **CCPA** (California): 45-day deadline, extendable to 90
- **Article 30 records**: Full audit trail per GDPR record-keeping requirements
- **Article 17(3) exceptions**: Billing/tax retention (7 years), security logs (90 days)
- **Tamper-evident records**: SHA-256 hashes of all artifacts at completion
