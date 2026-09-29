# Security Decisions

Every security scanner finding in this project gets one of four outcomes: **fixed**, **accepted** as a documented risk, **suppressed** because the finding doesn't apply to how the resource is used, or **suppressed as a false positive**. This file records each decision and the reasoning behind it, so the choices can be reviewed, challenged, and revisited.

Suppressions in the Terraform code are applied inline on the specific resource, with a short reason next to them. The same check still runs everywhere else in the code.

**Scanners:** [Checkov](https://www.checkov.io/) and [Trivy](https://trivy.dev/)

---

## Summary

| # | Finding | Resource | Outcome |
|---|---|---|---|
| 1 | No lifecycle configuration | Data bucket | Fixed |
| 2 | Not encrypted with a customer-managed KMS key | Data bucket | Fixed |
| 3 | No access logging | Data bucket | Fixed |
| 4 | Key policy grants `kms:*` on resource `*` | KMS key policy | Suppressed: false positive |
| 5 | Not encrypted with a customer-managed KMS key | Logs bucket | Suppressed: not supported |
| 6 | No cross-region replication | Data and logs buckets | Accepted |
| 7 | No event notifications | Data and logs buckets | Accepted |

---

## 1. Lifecycle configuration: Fixed

**Finding:** Checkov CKV2_AWS_61

**Why it matters:** Versioning keeps every old copy of an object indefinitely. Without cleanup, storage cost grows without limit, and failed multipart uploads leave invisible, billable fragments behind.

**What was done:** Old object versions expire 90 days after being replaced, and incomplete multipart uploads are removed after 7 days. The 90-day window keeps a recovery period for accidental overwrites or deletions.

---

## 2. Customer-managed KMS key: Fixed

**Findings:** Checkov CKV_AWS_145, Trivy AWS-0132 (HIGH)

**Why it matters:** With AWS-managed encryption, the key can't be controlled, restricted, or audited. A customer-managed key adds a second access check (anyone reading the data also needs permission to use the key), records every use of the key, and can be disabled to cut off access to the data immediately during an incident.

**What was done:**
- Customer-managed KMS key with automatic annual rotation and a 7-day deletion window
- Bucket encryption uses the key, with an S3 bucket key enabled to reduce KMS request volume and cost
- The read-only IAM role was granted `kms:Decrypt` on this key only. Without it, the role would be denied access to the encrypted objects despite having S3 read permission.
- An explicit key policy written in code, so who can use the key is visible in review instead of relying on an unstated default

---

## 3. Access logging: Fixed

**Findings:** Checkov CKV_AWS_18, Trivy AWS-0089 (LOW)

**Why it matters:** Without access logs, there is no record of who read, wrote, or deleted objects, and nothing to investigate from after an incident.

**What was done:**
- A dedicated logs bucket receives S3 server access logs from the data bucket
- The logs bucket has its own public access block, encryption, versioning, and lifecycle rule (logs are retained for 365 days)
- A bucket policy allows only the S3 logging service to write, only into the `access-logs/` prefix, and only on behalf of the data bucket in this account. The source bucket and account conditions prevent the logging service from being used to write another party's logs into this bucket (the "confused deputy" problem).

**Why the logs bucket does not log itself:** Logging the logs bucket would require another bucket, which would then need its own logging, and so on without end. The logs bucket is the end of the chain. Neither scanner flags this, since both recognize a logging destination bucket.

---

## 4. KMS key policy wildcards: Suppressed (false positive)

**Findings:** Checkov CKV_AWS_109, CKV_AWS_111, CKV_AWS_356

**What the scanner sees:** A policy document granting `kms:*` on resource `*`, which would be dangerously broad in an IAM policy.

**Why it doesn't apply:** This document is a **key policy**, attached to a single KMS key. In a key policy:
- Resource `*` means "this key," not every resource in the account
- The principal `arn:aws:iam::<account>:root` means "this account," which hands access decisions to IAM. It does not refer to the root user.

This is AWS's recommended default key policy. Actual access is limited by IAM, where the only grant is `kms:Decrypt` for the read-only role.

**Suppression scope:** These three checks are skipped on the key policy document only. They remain active for the IAM role's permissions policy.

---

## 5. Logs bucket without a customer-managed KMS key: Suppressed (not supported)

**Finding:** Checkov CKV_AWS_145 (logs bucket)

**Why it doesn't apply:** S3 server access logging cannot deliver logs to a bucket encrypted with a customer-managed KMS key. The logs bucket must use SSE-S3 (AES-256). Trivy's own guidance for AWS-0132 notes this exception, and Trivy does not flag the logs bucket.

**Result:** The logs bucket is still encrypted at rest, using AWS-managed keys.

---

## 6. Cross-region replication: Accepted

**Finding:** Checkov CKV_AWS_144 (both buckets)

**What it would add:** A continuously updated copy of each bucket in a second AWS region, to survive the loss of an entire region.

**Why it's accepted:**
- This is a disaster-recovery control, sized for business-critical data with a requirement to keep operating through a regional outage. This project holds demonstration data with no such requirement.
- It would roughly double storage cost and add a second region, a replication IAM role, and matching encryption and logging in that region.

**Controls already in place:**
- S3 Standard stores data across multiple Availability Zones within the region
- Versioning with a 90-day recovery window protects against accidental deletion and overwriting, which are far more common causes of data loss than a regional outage

**Revisit if:** the bucket starts holding data that must survive a regional outage, or a recovery requirement calls for failover to another region.

---

## 7. Event notifications: Accepted

**Finding:** Checkov CKV2_AWS_62 (both buckets)

**What it would add:** A message sent to a queue, topic, or function whenever objects are created or deleted.

**Why it's accepted:** There is no system that would receive or act on these events. Enabling notifications with nothing consuming them adds resources and cost without adding security.

**Controls already in place:** Server access logging (decision 3) already records every request to the data bucket for review and investigation.

**Revisit if:** a consumer is added, such as a SIEM ingesting S3 events for real-time alerting, or an automated workflow triggered by new uploads.
