# Runbook 01: Deploy AWS Control Tower Landing Zone

**Status:** Operator action required  
**Estimated time:** 45–60 minutes (CT setup) + 15–30 minutes (IaC wrapper)  
**Requires:** Management account console access with AdministratorAccess

---

## Overview

AWS Control Tower (CT) is deployed via the **AWS console**, not via `tofu apply`. CT
self-manages its own CloudFormation StackSets internally and will conflict with external
IaC if you attempt to manage CT resources directly with Terraform/OpenTofu resource blocks.

This runbook must be followed in order. Do NOT skip sections or run steps out of sequence.

After CT is live, the IaC wrapper at `management/ct-bootstrap/` reads the landing zone
state via data sources and exports account IDs and the landing zone ARN for downstream use
(Phase 2 AFT module). That unit contains **no resource blocks** — it only reads existing
CT state.

---

## Section 1: Pre-flight Gate

**You MUST run the pre-flight script before opening the CT console.** If the script exits
non-zero, fix all failures before proceeding. Do not continue with a failing pre-flight.

```bash
# From repo root
./scripts/preflight.sh
# Expected: 5 PASS lines, exit 0
```

The script checks:
1. Existing AWS Config recorders (Pitfall 1 — will block CT setup)
2. Conflicting SCPs that block CT service principals
3. IAM role conflicts (`AWSControlTowerExecution` pre-existence — Pitfall 2)
4. Organizations trusted access for CT service principals
5. Conflicting CloudTrail organization trails

If any check fails, the script prints a remediation command and exits 1. Fix all failures,
then re-run `./scripts/preflight.sh` until all 5 checks pass.

---

## Section 2: State Backend Gate

Verify the Terragrunt state backend exists before running any Terragrunt commands later
in this runbook. If the state backend is missing, the IaC wrapper step will fail.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api head-bucket --bucket "chain-vote-tofu-state-${ACCOUNT_ID}"
aws dynamodb describe-table --table-name chain-vote-tofu-locks --region us-east-1
# Both commands must succeed (exit 0).
# If either fails, run: ./scripts/bootstrap-state.sh
```

---

## Section 3: Enable CT Organizations Trusted Access

Before opening the CT console, ensure AWS Organizations trusted access is enabled for all
required CT service principals. These commands are **idempotent** — safe to run even if
access is already enabled.

```bash
aws organizations enable-aws-service-access --service-principal controltower.amazonaws.com
aws organizations enable-aws-service-access --service-principal config.amazonaws.com
aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com
aws organizations enable-aws-service-access --service-principal sso.amazonaws.com
```

These steps are frequently missing from AWS documentation and will cause CT setup to fail
silently if skipped.

Verify all four are enabled:
```bash
aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[*].ServicePrincipal' --output json
# Expected: array contains all four service principals above
```

---

## Section 4: Deploy CT Landing Zone via AWS Console

**Before starting:** Have the two unique email addresses ready for Log Archive and Audit
accounts. These emails must not be associated with any existing AWS account.

### Console steps (in order):

1. Sign in to the AWS **management account** console.

2. In the top search bar, type **Control Tower** and select **AWS Control Tower**.

3. Click **Set up landing zone**.

4. **Home Region:** Select `us-east-1 (US East - N. Virginia)`. Do not change this after
   setup — CT home region is permanent.

5. **Log archive account:**
   - Account email: enter your unique log-archive email address
   - Account name: `log-archive`
   - Record the email used — you will need it for verification

6. **Audit account:**
   - Account email: enter your unique audit email address
   - Account name: `audit`
   - Record the email used — you will need it for verification

7. **Foundational OU:** Accept the default name `Security`. Do NOT rename it.
   The Security OU is CT-managed and must not be modified via the console or IaC after setup.

8. **Additional OU:** Add `Sandbox`.
   CT requires at least one additional OU at setup time. `Sandbox` can be deleted after
   setup is complete. See Pitfall 5 note on OU registration ordering below.

9. Review the preview. CT will create:
   - A CloudTrail organization trail
   - AWS Config aggregator and recorder in all enrolled accounts
   - Two new accounts: log-archive and audit
   - IAM Identity Center (SSO) organization-wide
   - Two OUs: Security (foundational) and Sandbox (additional)

10. Click **Set up landing zone**. CT will begin provisioning.

11. **Wait for completion.** Estimated time: 30–60 minutes. Do not navigate away from the
    CT console during setup. Setup is complete when the status banner shows **Ready**.

> **Pitfall 7 — No console changes after IaC takeover:** Once CT is live and
> `management/ct-bootstrap/` is initialized, establish a no-console-changes policy.
> Changes made via the CT console after IaC is established will create drift that is
> invisible to `terragrunt plan`. See PITFALLS.md for remediation steps.

---

## Section 5: Post-Setup Verification

After CT status shows **Ready**, run these verification commands:

```bash
# Verify the landing zone ARN
aws controltower list-landing-zones --query 'landingZones[0].arn'
# Expected: a non-empty ARN string

# Verify Log Archive and Audit accounts exist and are ACTIVE
aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE`].[Name,Id,Email]' \
  --output table
# Look for rows with Name = 'log-archive' and Name = 'audit'

# Verify Organizations trusted access is still enabled for CT
aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[*].ServicePrincipal' --output json
# Expected: all four service principals from Section 3 are present
```

---

## Section 6: Record Account IDs

Capture the three account IDs. These are required inputs for
`management/ct-bootstrap/terraform.tfvars` (Task 2) and the AFT module in Phase 2.

```bash
MGMT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LOG_ARCHIVE_ID=$(aws organizations list-accounts \
  --query 'Accounts[?Name==`log-archive`].Id' --output text)
AUDIT_ID=$(aws organizations list-accounts \
  --query 'Accounts[?Name==`audit`].Id' --output text)

echo "Management account : ${MGMT_ACCOUNT_ID}"
echo "Log Archive account: ${LOG_ARCHIVE_ID}"
echo "Audit account      : ${AUDIT_ID}"
```

Save these values. Then populate the IaC wrapper tfvars:

```bash
# From repo root
cp management/ct-bootstrap/terraform.tfvars.example management/ct-bootstrap/terraform.tfvars

# Edit terraform.tfvars and fill in the three account IDs captured above
# (terraform.tfvars is .gitignored — do not commit it)
```

---

## Section 7: Initialize and Apply the IaC Wrapper

With CT live and `terraform.tfvars` populated, initialize the data source unit:

```bash
cd management/ct-bootstrap

# Initialize — downloads provider, configures remote state backend
terragrunt init

# Validate configuration (checks HCL syntax and provider schema)
terragrunt validate

# Plan — should show data source reads only, no resource changes
terragrunt plan

# Apply — reads CT state and writes outputs to remote state
terragrunt apply
```

Verify outputs:
```bash
terragrunt output
# Expected: four non-empty outputs:
#   landing_zone_arn      = "arn:aws:controltower:us-east-1:..."
#   log_archive_account_id = "1234567890XX"
#   audit_account_id       = "1234567890XX"
#   management_account_id  = "1234567890XX"
```

These output values are the inputs for Phase 2 (AFT module deployment).

---

## Section 8: Known Pitfalls

See `.planning/research/PITFALLS.md` for the full pitfall register. Key warnings:

| # | Pitfall | Impact | Caught by |
|---|---------|--------|-----------|
| 1 | Pre-existing AWS Config recorders | CT setup fails | `scripts/preflight.sh` check 1 |
| 2 | Pre-existing `AWSControlTowerExecution` IAM role | Account enrollment fails | `scripts/preflight.sh` check 3 |
| 5 | OU registration ordering (parent before child) | Nested OUs fail to register | Phase 1 plan 04 sequencing |
| 7 | CT console changes after IaC takeover | Invisible drift in `terragrunt plan` | No-console-changes policy (establish now) |

**Do NOT:**
- Modify SCPs on CT-managed OUs (Security OU)
- Register the `Security` OU manually in CT — it is auto-managed
- Run `tofu apply` on any resource that CT manages via CloudFormation StackSets
- Make changes to Log Archive or Audit account settings via the console after CT setup

---

## Completion Checklist

- [ ] `./scripts/preflight.sh` exits 0 (all 5 checks pass)
- [ ] State backend verified (S3 bucket + DynamoDB table exist)
- [ ] Trusted access enabled for all 4 CT service principals
- [ ] CT console shows status **Ready**
- [ ] Log Archive account ID captured and verified
- [ ] Audit account ID captured and verified
- [ ] `management/ct-bootstrap/terraform.tfvars` populated with 3 account IDs
- [ ] `terragrunt init && terragrunt apply` succeeds in `management/ct-bootstrap/`
- [ ] `terragrunt output` returns all 4 non-empty values
- [ ] No-console-changes policy established with team

Once all items are checked, Phase 1 Plan 02 is complete. Proceed to Plan 03 (OU structure).
