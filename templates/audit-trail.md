# GDPR Compliance Audit Trail
## Data Subject Request: {request_id}

**Classification:** CONFIDENTIAL — Data Protection Record
**Document Type:** Article 30 Processing Record / DSR Audit Trail
**Retention Period:** 5 years from request completion date

---

## 1. Request Receipt

| Field | Value |
|---|---|
| Request ID | {request_id} |
| Received At | {received_at} |
| Received Via | {channel} |
| Subject Name | {subject_name} |
| Subject Email | {subject_email} |
| Request Type | {request_type} |
| Applicable Regulation | {regulation} |
| Identity Verified | {identity_verified} |
| Identity Verification Method | {verification_method} |

## 2. Classification

| Field | Value |
|---|---|
| Request Sub-Type | {sub_type} |
| Complexity | {complexity} |
| Regulatory Deadline | {deadline} |
| Extension Used | {extension_used} |
| Extension New Deadline | {extension_deadline} |
| Prior Requests | {prior_requests_count} |

**Classification Reasoning:**
{classification_reasoning}

## 3. Data Discovery

### Sources Searched

| Source | Data Found | Categories | Records | Sensitive | Retention Exception |
|---|---|---|---|---|---|
{data_sources_table}

### Inventory Summary

**Total data categories found:** {total_categories}
**Total systems with personal data:** {systems_with_data}
**Systems with retention exceptions:** {systems_with_exceptions}

## 4. Actions Taken

{actions_taken}

### Exceptions Applied

{exceptions_applied}

### Third-Party Notifications

{third_party_notifications}

## 5. Outcome

| Field | Value |
|---|---|
| Status | {final_status} |
| Completed At | {completed_at} |
| Response Letter Sent | {response_sent} |
| Completed Within Deadline | {within_deadline} |
| Days to Complete | {days_to_complete} |

## 6. Artifact Integrity

| Artifact | SHA-256 Hash |
|---|---|
{artifact_hashes}

## 7. Processing Record

This request was processed in accordance with:
- GDPR Article 12 (transparent information and modalities)
- GDPR Article 17 (right to erasure) / Article 15 (right of access) / Article 20 (data portability)
- Our Data Protection Policy (version {policy_version})

**Processed by:** AO GDPR Pipeline (automated, with DPO oversight)
**DPO Review:** {dpo_review_status}

---
*This document constitutes part of the controller's records of processing activities under GDPR Article 30.*
