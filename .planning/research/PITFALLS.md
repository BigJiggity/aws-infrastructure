# Domain Pitfalls: CT + AFT + OpenTofu + Terragrunt

**Domain:** AWS Control Tower + AFT + OpenTofu + Terragrunt, existing org, 6-account vending
**Researched:** 2026-06-16
**Confidence:** HIGH (CT/AFT docs), MEDIUM (OpenTofu+AFT interplay), HIGH (Terragrunt docs)

---

## Critical Pitfalls

Mistakes that cause rewrites, unrecoverable state, or multi-hour AWS support calls.

---

### Pitfall 1: Pre-existing AWS Config Resources Block CT Setup

**What goes wrong:** Control Tower setup fails immediately if any account (management, log archive, audit) already has an AWS Config configuration recorder or delivery channel. This is the single most common blocker for CT-on-existing-org deployments.

**Why it happens:** CT wants to own Config recorders across all accounts. If a recorder exists, CT's CloudFormation stack sets fail with a conflict error.

**Consequences:** Landing zone setup halts mid-flight. Partial stack set deployments require manual cleanup before retrying. Can leave accounts in a broken governance state.

**Prevention:**
1. Before running CT setup, audit every target account:
   ```bash
   aws configservice describe-configuration-recorders
   aws configservice describe-delivery-channels
   ```
2. Stop, then delete recorders and delivery channels in management account:
   ```bash
   aws configservice stop-configuration-recorder --configuration-recorder-name <name>
   aws configservice delete-delivery-channel --delivery-channel-name <name>
   aws configservice delete-configuration-recorder --configuration-recorder-name <name>
   ```
3. For member accounts that will be enrolled, do the same before enrollment, or use the CT "Enroll accounts with existing Config resources" procedure (requires AWS support allowlisting in some cases).

**Detection:** CT console shows "Landing zone setup failed" immediately. CloudFormation events in the management account reference `AWS::Config::ConfigurationRecorder` resource conflicts.

**Phase:** Must be addressed before Phase 1 (CT deployment). Make this a pre-flight checklist item.

---

### Pitfall 2: Pre-existing IAM Roles Block Account Enrollment

**What goes wrong:** CT creates several IAM roles in each enrolled account (`AWSControlTowerAdmin`, `AWSControlTowerCloudTrailRole`, `AWSControlTowerConfigRecorderRole`, etc.). If any of these already exist (from a previous partial enrollment attempt, or manual creation), enrollment fails with a hard error:

```
AWS Control Tower cannot create the IAM role aws-controltower-AdministratorExecutionRole because the role already exists.
```

**Why it happens:** CT's stack sets do not perform upserts — they fail if the resource exists.

**Consequences:** Account enrollment is stuck. The account appears partially enrolled in CT but is ungoverned. Requires manual role deletion and re-enrollment.

**Prevention:**
1. Before enrolling each account, check for and delete CT-named roles:
   ```bash
   aws iam list-roles | grep -i controltower
   ```
2. Delete any `aws-controltower-*` or `AWSControlTower*` roles that exist from partial previous attempts.
3. Verify the `AWSControlTowerExecution` role is present (required) and has `AdministratorAccess` with a trust to the management account.

**Detection:** Enrollment fails in CT console with "IAM role already exists" error. Check CloudFormation stack set instances for `FAILED` status.

**Phase:** Phase 1 (CT deployment) and Phase 3 (account enrollment). Pre-check before each enrollment.

---

### Pitfall 3: AFT Does Not Natively Support OpenTofu — Requires a Workaround

**What goes wrong:** AFT's `terraform_distribution` input only accepts `"oss"` (Terraform Community Edition), `"tfc"` (Terraform Cloud), or `"tfe"` (Terraform Enterprise). There is no `"opentofu"` option. AFT's internal CodeBuild buildspecs call the `terraform` binary by name.

**Why it happens:** AFT is an AWS-owned module that targets HashiCorp Terraform. OpenTofu is a separate binary (`tofu`). AWS has not released native OpenTofu support in AFT's distribution parameter.

**Consequences:** If you deploy AFT with `terraform_distribution = "oss"` and set `terraform_version` to a version, CodeBuild will download the Terraform OSS binary — not OpenTofu. Your AFT pipelines will use Terraform despite the repo-wide intent to use OpenTofu.

**The actual workaround (from PROJECT.md key decisions):**
The `aft_feature_flags` does not solve this directly. The approach referenced in the project (`aft_tf_distribution = "TF"`) appears to be referencing an older or community-documented pattern. The actual mechanism is:
- Deploy the AFT module itself using OpenTofu locally (your Terragrunt wrapper runs `tofu` to apply the AFT module)
- Set `terraform_distribution = "oss"` and `terraform_version` to a compatible version for AFT's internal pipelines
- Accept that AFT's internal CodeBuild jobs run Terraform OSS, not OpenTofu, for account provisioning
- Use OpenTofu for everything outside the AFT pipeline (CT controls, account customization wrappers via Terragrunt)

**Important:** There is no AFT-native OpenTofu support. The OpenTofu choice applies to your local Terragrunt orchestration, not to what runs inside AFT's CodeBuild pipeline. Do not expect to replace AFT's internal `terraform` binary with `tofu` without forking AFT.

**Warning signs:**
- If you set `terraform_version` to a value and CodeBuild logs show `tofu: command not found` — you've gone too far
- If you try to set `terraform_distribution` to anything other than `oss`/`tfc`/`tfe`, the module will error on `tofu` apply

**Prevention:**
- Accept the split: OpenTofu for local/Terragrunt orchestration; Terraform OSS inside AFT's CodeBuild
- Pin `terraform_version = "1.9.x"` or later (last BSL-licensed version with broad provider support) in the AFT module
- Keep AFT at the latest tagged release — check `github.com/aws-ia/terraform-aws-control_tower_account_factory/releases`

**Phase:** Phase 1 (AFT bootstrap). Document the split explicitly. Do not promise "full OpenTofu pipeline" — it's only partially true.

---

### Pitfall 4: AFT Pipeline Failures Are Silent Until You Know Where to Look

**What goes wrong:** An account request push triggers nothing visible. Or a CodePipeline run shows green but the account never appears. Or a CodeBuild stage fails and you don't know which log to check.

**Why it happens:** AFT uses a multi-stage pipeline: Lambda (request trigger) → SQS → Step Functions → Service Catalog → CodeBuild (customizations). Failures at any stage emit to different log destinations.

**Debugging path (in order):**
1. **Lambda trigger**: Check CloudWatch log group for `aft-account-request-action-trigger` Lambda. Match timestamp to your git push.
2. **Step Functions**: In the AFT management account, open the `aft-account-provisioning` state machine. Look for failed executions.
3. **Service Catalog**: In the CT management account, check Account Factory provisioned products for `FAILED` or `IN_PROGRESS` (stuck) status.
4. **CodeBuild customizations**: CloudWatch log group `/aws/codebuild/aft-account-customizations`. Filter by account ID using CloudWatch Logs Insights:
   ```
   fields @timestamp, log_message.account_id, log_message.detail, @logStream
   | sort @timestamp desc
   | filter log_message.account_id == "YOUR-ACCOUNT-ID"
   ```
5. **SNS failure topic**: Subscribe to the `aft-failure-notifications` SNS topic in the AFT management account for automatic failure alerts.

**Prevention:**
- Subscribe to `aft-failure-notifications` SNS before running any account requests
- Never push multiple account requests simultaneously on first deployment — push one, verify end-to-end, then batch
- Retain CloudWatch log groups — AFT sets retention to "Never Expire" by default, which is fine

**Detection:** Account doesn't appear in CT console within 20 minutes of a push. Service Catalog shows `IN_PROGRESS` for more than 30 minutes.

**Phase:** Phase 2 (AFT pipeline setup) and Phase 3 (account provisioning). Set up SNS alerting before any account requests.

---

### Pitfall 5: Nested OU Registration Has Strict Parent-First Ordering

**What goes wrong:** Attempting to register `Root > chain-vote-ai > dev` in CT fails because CT requires each OU in the hierarchy to be registered before its children. You cannot register a child OU if its parent OU has not been registered (and successfully completed registration).

**Why it happens:** CT enforces: parent must be registered before child. An OU can only be registered if all ancestor OUs have previously been registered.

**The specific constraint for this project:**
The target structure is `Root > {chain-vote-ai, chain-vote-voting} > {dev, staging, prod}`. That means:
1. Register `chain-vote-ai` OU (under Root) — wait for completion
2. Register `chain-vote-voting` OU (under Root) — wait for completion
3. Register `chain-vote-ai/dev`, `chain-vote-ai/staging`, `chain-vote-ai/prod` — parent must be done
4. Register `chain-vote-voting/dev`, etc.

You cannot batch these in parallel if using `Register OU` workflow. Terragrunt `run-all` will fail if it tries to register child OUs before parent registration completes.

**Additional constraint:** CT does not allow registering any OU under the core Security OU. The management account's root OU registration is automatic (it's done as part of CT setup).

**Prevention:**
- Model OU registration as sequential Terragrunt units with explicit `dependency` blocks
- Use `depends_on` or Terragrunt's `dependencies` to enforce ordering
- Do not use `run-all` for OU registration — orchestrate unit by unit

**Detection:** CT console shows "OU registration failed" with message about parent not being registered. CT API returns `AccessDeniedException` or `ConstraintViolationException` if parent isn't ready.

**Phase:** Phase 1 (CT deployment). IaC must model the OU tree as a DAG with explicit parent-before-child dependencies.

---

### Pitfall 6: Service Catalog "IN_PROGRESS" Blocks Subsequent Account Operations

**What goes wrong:** AFT sends an account request while another CT operation is in progress (another account provisioning, a landing zone update, an OU re-registration). Service Catalog rejects the new request and the AFT pipeline appears to silently fail or gets stuck.

**Why it happens:** CT allows only one concurrent account factory operation per organization. This is a known AFT limitation (tracked in `aws-ia/terraform-aws-control_tower_account_factory` issue #363).

**Consequences:** If you push all 6 account requests at once, 5 of them will likely fail or queue incorrectly. You may see accounts stuck in `IN_PROGRESS` indefinitely in Service Catalog, requiring manual intervention.

**Prevention:**
- Push account requests one at a time on first deployment. Verify each account reaches `SUCCEEDED` in Service Catalog before pushing the next.
- After all 6 accounts are provisioned, subsequent re-invocations via `aft-invoke-customizations` handle concurrency internally (max 5 concurrent).
- For CI/CD: serialize account request merges with branch protection (one PR merged at a time), or add a pipeline gate.

**Re-invocation idempotency:** Re-pushing an existing account request (no changes) re-triggers customizations but does not re-provision the account via Service Catalog. This is safe and expected. The AFT pipeline is idempotent for account customizations but not for initial provisioning while other operations are running.

**Detection:** Service Catalog provisioned product status shows `IN_PROGRESS` for > 30 minutes. AFT Step Functions shows waiting/retrying on the service catalog step.

**Phase:** Phase 3 (account provisioning). Serial provisioning is a hard requirement on first run.

---

### Pitfall 7: CT Console Changes Create IaC Drift That Is Hard to Detect

**What goes wrong:** Someone makes a change in the CT console (moves an account between OUs, enables/disables a control, updates landing zone settings) and your Terragrunt/OpenTofu state no longer matches reality. The next `tofu plan` may show unexpected diffs or, worse, undo the console change silently on `apply`.

**Why it happens:** CT resources managed by Terraform/OpenTofu via the `aws_controltower_*` provider resources track state locally. Console-driven changes update the AWS backend but not the local state file. CT also generates its own EventBridge drift events but these are separate from Terraform state drift.

**Specific drift types CT tracks:**
- `ACCOUNT_MOVED_BETWEEN_OUS` — moving an account in Organizations console
- `TRUSTED_ACCESS_DISABLED` — disabling CT trusted access in Organizations
- SCP modifications on CT-managed OUs
- Landing zone configuration changes outside IaC

**Consequences:**
- Console-moved account: CT raises a drift event; SCP/Config rules from old OU are NOT automatically removed. New OU controls don't apply until re-registration.
- If IaC then runs and moves the account back to match state, it creates a double-move drift cycle.
- Trusted access disabled: CT stops receiving org change events; enrollment and OU registration fail silently.

**Prevention:**
- Establish a policy: no CT console changes once IaC owns it. All changes via PRs to this repo.
- Enable CT drift notifications via EventBridge and route to a visible channel (SNS → email at minimum) during active development.
- After any manual intervention, run `tofu plan` immediately and reconcile before the next change.
- Consider `tofu import` for any accounts or OUs created via console before IaC takeover.

**Detection:** CT console shows "Drift detected" banner. EventBridge emits `DriftType: ACCOUNT_MOVED_BETWEEN_OUS` or `TRUSTED_ACCESS_DISABLED` events.

**Phase:** Phase 1–3. Establish the "no console changes" rule at kickoff. Automate drift EventBridge routing in Phase 1.

---

### Pitfall 8: AWSControlTowerExecution Role Confusion in Terragrunt Cross-Account Runs

**What goes wrong:** Developers assume the `AWSControlTowerExecution` role in member accounts is available for Terragrunt to assume for general infrastructure work. Attempting to use it for Terragrunt runs in member accounts fails or creates security issues.

**Why it happens:** `AWSControlTowerExecution` is a CT-internal role (trust: management account, policy: AdministratorAccess). It is intended exclusively for CT's own CloudFormation stack set operations — not for human or CI/CD use. Using it for Terragrunt runs creates two problems:
1. CT may revert changes it considers "out of scope" for that role
2. The role has no principal restrictions, making it a lateral movement vector (documented security risk)

**The correct pattern for Terragrunt cross-account access:**
- Create a separate deployment role in each member account (e.g., `TerragruntDeployRole`) during AFT customizations
- Trust only the CI/CD principal (e.g., the AFT management account's CodeBuild role, or a specific GitHub Actions role via OIDC)
- Use that role for all Terragrunt plan/apply runs targeting member accounts
- The AFT customizations pipeline already creates `AWSAFTExecution` role in each account — this is the correct one to use within AFT pipelines

**Detection:** Terragrunt fails with `AccessDenied` when assuming the execution role, or succeeds but CT later reports drift because the role was used outside expected CT workflows.

**Phase:** Phase 2 (AFT pipeline configuration). Define the deployment role in AFT account customizations, not as an afterthought.

---

### Pitfall 9: Terragrunt Binary Detection: OpenTofu vs Terraform

**What goes wrong:** On a machine or CodeBuild image where both `terraform` and `tofu` are installed, Terragrunt may pick the wrong binary. In newer Terragrunt versions (post-0.52.0), `tofu` is preferred when found; in older versions, `terraform` is preferred. This creates non-deterministic behavior across developer machines and CI.

**Why it happens:** Terragrunt auto-detects which binary to use based on PATH order and version. The default has changed between Terragrunt versions, creating inconsistency.

**Prevention:**
- Explicitly set the binary in all `terragrunt.hcl` root configs:
  ```hcl
  terraform_binary = "tofu"
  ```
  Or via environment variable in CI: `export TG_TF_PATH=tofu`
- Pin Terragrunt version in `.terraform-version` or `.opentofu-version` (use `tenv` for version management)
- Ensure CodeBuild images (used by your local Terragrunt, not AFT internals) only have `tofu` in PATH, not both

**Detection:** `terragrunt version` output shows unexpected binary. Plans run correctly locally but fail in CI with "binary not found" or use wrong version.

**Phase:** Phase 1 (local dev setup and CI configuration). Pin this early.

---

### Pitfall 10: S3 Backend Race Condition During Parallel `run-all` on First Apply

**What goes wrong:** Running `terragrunt run-all apply` on a fresh account where the state bucket doesn't yet exist causes multiple Terragrunt units to attempt bucket creation simultaneously. This results in `BucketAlreadyExists` or `BucketAlreadyOwnedByYou` errors from roughly 10% of parallel workers.

**Why it happens:** Terragrunt auto-creates the S3 backend bucket and DynamoDB table if they don't exist. With `run-all`, multiple modules start simultaneously, each trying to create the same bucket.

**Consequences:** Some units fail on init, leaving them with no state backend. Subsequent applies may create orphaned resources.

**Prevention:**
- Bootstrap the state bucket before running any `run-all`. Use a dedicated `bootstrap` unit that creates the S3 bucket and DynamoDB table, and has no dependencies on other units.
- All other units should have a `dependency` on the bootstrap unit or use `prevent_destroy = true` on the bucket.
- For OpenTofu >= 1.10 with Terragrunt using native S3 locking (`use_lockfile = true`): you still need the bucket to exist first; the locking mechanism change doesn't eliminate the creation race.

**Detection:** `run-all apply` output shows `BucketAlreadyExists` errors on `tofu init` for some modules. State files are missing for failed modules.

**Phase:** Phase 1 (state infrastructure). Create a `bootstrap` unit as the first thing deployed, sequentially.

---

### Pitfall 11: AFT Bootstrap Ordering — What Must Be Done Manually Before IaC

**What goes wrong:** The AFT module requires several pre-conditions that cannot be automated by the AFT module itself. Attempting to apply the AFT module before meeting these conditions produces cryptic failures.

**Required manual steps before the AFT Terragrunt module can be applied:**

1. **CT landing zone must exist and be healthy** — AFT has a hard prerequisite on a functioning CT landing zone. There is no IaC shortcut.

2. **AFT management account must be provisioned** — This is a dedicated account (separate from CT management account) created via CT Account Factory in the console or via Service Catalog. AFT is then deployed into this account. You cannot deploy AFT into the CT management account.

3. **Log archive and audit account IDs must be known** — The AFT module requires `log_archive_account_id`, `audit_account_id`, and `ct_management_account_id` as inputs. These are only knowable after CT setup. You cannot get them from IaC until CT exists.

4. **Git source repos must exist before AFT applies** — AFT needs 4 git repositories for its pipeline (account-requests, global-customizations, account-customizations, account-provisioning-customizations). If using a VCS other than CodeCommit (e.g., GitHub via CodeConnections), the connection must be manually authorized in the AWS console after first deployment.

5. **CodeConnections (GitHub) requires manual OAuth approval** — Even if you provision the CodeStar connection via IaC, it requires a human to click "Authorize" in the AWS console before the CodePipeline can pull from GitHub. This is a one-time manual step that cannot be automated.

**Prevention:**
- Document the manual bootstrap steps as a Phase 1 runbook. IaC cannot replace these.
- Capture the log archive, audit, and AFT management account IDs into a `tfvars` file or AWS SSM parameters after CT setup completes.
- Plan for the CodeConnections manual auth step — don't expect CI to work immediately after first apply.

**Phase:** Phase 1 (CT landing zone) must complete before Phase 2 (AFT bootstrap). Sequence is: manual CT setup → capture account IDs → AFT Terragrunt apply → manual CodeConnections auth → first account request push.

---

## Moderate Pitfalls

### Pitfall: AFT Terraform Version Must Be Pinned and Compatible with Provider Versions

**What goes wrong:** Setting `terraform_version = "latest"` or not pinning provider versions in AFT customizations causes version drift. CodeBuild pulls the latest Terraform OSS binary, which may break provider API calls or introduce behavior changes.

**Prevention:** Always pin `terraform_version` in the AFT module input (e.g., `"1.9.8"`). Pin provider versions in all customization repos' `versions.tf` files. Test upgrades in a lower environment first.

**Phase:** Phase 2 (AFT bootstrap). Establish version pins before first account request.

---

### Pitfall: OU Registration Limit (1000 Accounts Per OU)

**What goes wrong:** An OU with more than 1000 directly nested accounts cannot be registered or re-registered in CT.

**Relevance for this project:** With only 6 accounts this is not an immediate concern, but the project's OU structure (`chain-vote-ai > {dev, staging, prod}`) will never approach this limit. Document the constraint for future growth — if accounts per workload OU exceed 1000, re-registration triggers must update provisioned products individually rather than re-registering the OU.

**Prevention:** For this project, no action needed. For future growth, track account counts per OU.

**Phase:** Not relevant for current scope. Note in architecture docs for future.

---

### Pitfall: SCP on CT-Managed OUs Must Not Be Modified Outside CT

**What goes wrong:** Editing SCPs attached to CT-registered OUs (via Organizations console or external IaC) puts CT into a "controls unknown state" that requires a landing zone reset or OU re-registration to fix.

**Why it happens:** CT tracks SCP content as part of its control verification. External modifications invalidate CT's internal model.

**Prevention:**
- Only modify CT-managed SCPs through CT's controls API or console.
- For custom SCPs beyond CT defaults, attach them to OUs that CT does not manage, or use CT's proactive/preventive control mechanisms.
- The project is currently out-of-scope for custom SCPs — this becomes critical if that changes.

**Detection:** CT console shows controls in "Configuration change detected" or "Unknown state" for an OU.

**Phase:** Relevant if/when custom SCPs are added (currently out of scope).

---

### Pitfall: Terragrunt `run-all` Destroy Cascade Without Parallelism Control

**What goes wrong:** `terragrunt run-all destroy` with default parallelism destroys resources in an order that violates dependencies, causing state corruption when a resource that other resources depend on is destroyed first.

**Prevention:** Always use `--terragrunt-parallelism 1` for destroy operations. Consider adding `prevent_destroy = true` on foundational resources (state bucket, CT-managed roles) to add a safety check.

**Phase:** Ongoing operational concern. Add to runbooks before any teardown operations.

---

## Minor Pitfalls

### Pitfall: AFT `aft_feature_flags` — Misunderstanding What They Control

**What goes wrong:** Developers assume `aft_feature_flags` controls OpenTofu distribution. It does not. These flags control:
- `aft_feature_cloudtrail_data_events` — enables S3/Lambda CloudTrail data event logging (cost impact)
- `aft_feature_enterprise_support` — enrolls accounts in Enterprise Support
- `aft_feature_delete_default_vpcs_enabled` — deletes default VPCs in all regions on account creation

`aft_feature_delete_default_vpcs_enabled = true` is a safe default for a security posture. The others have cost implications. None relate to the binary used inside CodeBuild.

**Prevention:** Read the flag definitions before setting them. Default VPC deletion is recommended but irreversible per-account without manual recreation.

**Phase:** Phase 2 (AFT module configuration).

---

### Pitfall: AFT Account Email Must Be Globally Unique and Owned

**What goes wrong:** AFT account requests require a unique email address per account. Reusing an email from a previously closed account, or using an alias that someone else could also submit, causes account creation to fail.

**Prevention:** Use a consistent naming scheme with email subaddressing (e.g., `aws+chain-vote-ai-dev@yourdomain.com`) if your domain supports it. Verify the email pattern before first account request push.

**Phase:** Phase 3 (account provisioning). Define email scheme before writing account request files.

---

### Pitfall: Terragrunt Provider Cache in CodeBuild Needs Explicit Configuration

**What goes wrong:** Without a shared provider cache, each CodeBuild run downloads all providers from the registry. This is slow, consumes bandwidth, and occasionally fails on registry timeouts. In AFT's CodeBuild environment, this is managed by AFT's buildspecs, but for external Terragrunt runs (your own CodeBuild or GitHub Actions), providers are re-downloaded per run.

**Prevention:** Configure `TG_PROVIDER_CACHE=1` and point `TG_PROVIDER_CACHE_DIR` to an EFS mount or a pre-warmed layer in your CI environment. For local development, use `~/.terraform.d/plugin-cache` or `~/.tenv` with `tenv` as the version manager.

**Phase:** Phase 2 (CI/CD configuration). Not blocking but affects pipeline speed.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|------------|---------------|------------|
| Phase 1: CT landing zone setup | Pre-existing Config recorders block setup | Audit and delete before applying CT |
| Phase 1: CT landing zone setup | Existing SCPs conflict with CT's FullAWSAccess requirement | Review all existing SCPs; CT must have FullAWSAccess on root |
| Phase 1: CT landing zone setup | Trusted access to Organizations disabled by existing policy | Enable explicitly before CT setup |
| Phase 1: OU registration | Parent OU not registered before child OU | Enforce DAG ordering in Terragrunt dependency blocks |
| Phase 1: State backend | S3 bucket creation race during first `run-all` | Bootstrap state bucket as a prerequisite unit |
| Phase 2: AFT bootstrap | AFT management account not pre-created | Create AFT account via CT Account Factory console first |
| Phase 2: AFT bootstrap | CodeConnections requires manual OAuth authorization | Plan for manual authorization step post-apply |
| Phase 2: AFT + OpenTofu | AFT's internal CodeBuild uses Terraform OSS, not OpenTofu | Document the split; set terraform_version pin explicitly |
| Phase 2: AFT configuration | Wrong `aft_feature_flags` assumptions | Read each flag; VPC deletion is safe; CloudTrail data events have cost impact |
| Phase 3: Account provisioning | Concurrent account requests cause Service Catalog conflicts | Provision accounts serially on first run |
| Phase 3: Account enrollment | Pre-existing IAM roles (AWSControlTower*) block enrollment | Pre-check and delete conflicting roles |
| Phase 3: Account email | Non-unique account email fails provisioning | Define email scheme before writing account requests |
| All phases | CT console changes create IaC drift | No-console-changes policy from day one |
| All phases | Terragrunt picks wrong binary (terraform vs tofu) | Pin `terraform_binary = "tofu"` in root terragrunt.hcl |

---

## Sources

- AWS Control Tower User Guide — Enrollment Prerequisites: https://docs.aws.amazon.com/controltower/latest/userguide/enrollment-prerequisites.html
- AWS Control Tower User Guide — About Enrolling Existing Accounts: https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html
- AWS Control Tower User Guide — Manually Enroll Existing Account: https://docs.aws.amazon.com/controltower/latest/userguide/enroll-manually.html
- AWS Control Tower User Guide — Troubleshooting: https://docs.aws.amazon.com/controltower/latest/userguide/troubleshooting.html
- AWS Control Tower User Guide — AFT Troubleshooting Guide: https://docs.aws.amazon.com/controltower/latest/userguide/account-troubleshooting-guide.html
- AWS Control Tower User Guide — AFT Getting Started: https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html
- AWS Control Tower User Guide — Version Supported: https://docs.aws.amazon.com/controltower/latest/userguide/version-supported.html
- AWS Control Tower User Guide — AFT Customization Options: https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html
- AWS Control Tower User Guide — Nested OUs: https://docs.aws.amazon.com/controltower/latest/userguide/nested-ous.html
- AWS Control Tower User Guide — Governance Drift: https://docs.aws.amazon.com/controltower/latest/userguide/governance-drift.html
- AWS Control Tower User Guide — Limits: https://docs.aws.amazon.com/controltower/latest/userguide/limits.html
- AWS Control Tower User Guide — Extend Governance to Existing Org: https://docs.aws.amazon.com/controltower/latest/userguide/about-extending-governance.html
- AWS Control Tower User Guide — Existing Config Resources: https://docs.aws.amazon.com/controltower/latest/userguide/existing-config-resources.html
- Terragrunt Docs — S3 Backend: https://terragrunt.gruntwork.io/docs/features/units/state-backend/
- Terragrunt Docs — Provider Cache Server: https://terragrunt.gruntwork.io/docs/features/caching/provider-cache-server/
- AFT GitHub Repository — Service Catalog IN_PROGRESS Issue #363: https://github.com/aws-ia/terraform-aws-control_tower_account_factory/issues/363
- Terragrunt GitHub — OpenTofu Binary Detection Issue #3168: https://github.com/gruntwork-io/terragrunt/issues/3168
- Terragrunt GitHub — OpenTofu Binary Detection Issue #3172: https://github.com/gruntwork-io/terragrunt/issues/3172
- Medium — AFT Lessons from the Trenches: https://medium.com/practical-aws/account-factory-for-terraform-lessons-from-the-trenches-7e86a5c4d3ee
- Cevo — Control Tower in Existing Organization: https://cevo.com.au/post/control-tower-breaking-fixing-and-onboarding-in-an-existing-aws-organization-part-2/
- Gruntwork Blog — Terragrunt + OpenTofu: https://www.gruntwork.io/blog/terragrunt-opentofu-better-together
