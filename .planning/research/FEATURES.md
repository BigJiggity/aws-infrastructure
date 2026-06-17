# Feature Landscape: AWS Control Tower + AFT

**Domain:** Multi-account AWS governance with automated account vending
**Project:** chain-vote — 6 accounts across 2 workload OUs, greenfield CT deployment
**Researched:** 2026-06-16
**Sources:** AWS Control Tower User Guide (Context7, HIGH confidence); AFT AWS docs; WebSearch for pitfalls and patterns

---

## Table Stakes

Features you must have for a working, non-broken CT+AFT setup. Missing any of these means the deployment is incomplete or fragile.

### Control Tower Landing Zone

| Feature | Why Required | Complexity | Notes |
|---------|--------------|------------|-------|
| Security OU with Log Archive + Audit accounts | CT will not deploy without these two shared accounts | Low setup, mandatory | Must exist in org before CT deploy; CT baselines them with SCPs and Config |
| IAM Identity Center (SSO) enabled | CT account provisioning requires SSO for the AWSAccountFactory permission set | Low (auto-configured) | CT enables and owns SSO; do not configure SSO independently before CT |
| CloudTrail org-level trail | Mandatory CT control; audit log of all API calls org-wide | Zero — CT creates it | Written to Log Archive S3; CT SCP prevents deletion or modification |
| AWS Config enabled in all accounts | Mandatory CT control; Config is the backbone of detective guardrails | Zero — CT deploys it | CT v4.0 changed Config architecture; be on LZ 4.x |
| Mandatory preventive SCPs | ~20 SCPs applied automatically to all CT-managed OUs | Zero — CT manages them | Includes: no CloudTrail disable, no Log Archive bucket delete, no Config rule delete, no IAM Identity Center changes |
| Mandatory detective guardrails | Config rules automatically applied on enrollment | Zero — CT manages them | Detect CloudTrail not enabled, Config not enabled, root MFA missing, etc. |
| OU registration | OUs must be explicitly registered with CT before accounts can be enrolled in them | Low | Custom OUs (non-Security) must be registered; parent OU must be registered before child OUs |

### AFT Pipeline Infrastructure

| Feature | Why Required | Complexity | Notes |
|---------|--------------|------------|-------|
| AFT management account | Separate account hosting all AFT CodePipeline, Lambda, DynamoDB, Step Functions resources | Low (declared in module input) | Can be the management account or a dedicated account; for simplicity this project uses the management account |
| AFT Terraform module deployment | The `aws-ia/terraform-aws-control_tower_account_factory` module wires up the entire pipeline | Medium | One-time deploy; sets up 4 Git repos and all pipeline infrastructure |
| 4 Git repositories | `aft-account-request`, `aft-global-customizations`, `aft-account-customizations`, `aft-account-provisioning-customizations` | Low | Repos are the source-of-truth inputs to the pipeline; CodePipeline polls them |
| account-request file per account | One `.tf` file per account in `aft-account-request` triggers vending | Low per account | Contains `control_tower_parameters`, `account_tags`, `custom_fields`, `account_customizations_name` |
| `control_tower_parameters` block | Required: AccountEmail, AccountName, ManagedOrganizationalUnit, SSOUserEmail, SSOUserFirstName, SSOUserLastName | Low | These CANNOT be changed post-provisioning (except ManagedOrganizationalUnit for moves) |
| S3 + DynamoDB AFT state backend | AFT stores its own Terraform state and account metadata in DynamoDB | Low (module creates it) | Separate from your orchestration state; AFT manages its own backend |
| AWSAFTExecution IAM role | Created in each vended account; AFT uses it to run customizations | Zero — AFT creates it | Do not delete; needed for re-invoke |

### Account Enrollment

| Feature | Why Required | Complexity | Notes |
|---------|--------------|------------|-------|
| Account baseline on enrollment | CT deploys 6+ CloudFormation StackSets into each enrolled account: CloudTrail, Config, IAM roles, CloudWatch | Zero — automatic | Takes 15-30 min per account; do not interrupt |
| SCP inheritance on OU placement | Preventive controls propagate down to nested OUs automatically; no per-account action needed | Zero — automatic | Preventive SCPs affect accounts even in unregistered nested OUs |
| Mandatory controls applied on enrollment | Detective Config rules and SSO permission sets are applied when account is enrolled into a registered OU | Zero — automatic | |

---

## Differentiators

Features that are not required for CT+AFT to work, but add governance value and are the reason you chose AFT over basic CT Account Factory.

### AFT Customization Layers

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Global customizations | Apply the same Terraform/bash/Python to every AFT-vended account; e.g., create a standard `deploy` IAM role, enable Security Hub, set account-level budget alarms | Low–Medium | Runs on every account vend and every re-invoke; ideal for baseline security posture |
| Account customizations | Apply account-specific Terraform to a named account type; e.g., `chain-vote-ai` vs `chain-vote-voting` get different IAM boundaries or resource configs | Medium | Set `account_customizations_name` in the account-request file to match a folder in `aft-account-customizations` |
| `custom_fields` metadata → SSM params | Arbitrary key-value metadata attached to each account-request; becomes SSM parameters in the account; customization scripts can branch on them | Low | E.g., `environment = "prod"` lets global customizations apply stricter settings to prod |
| Account tags (`account_tags`) | Business tags (CostCenter, Owner, Environment, Workload) applied at the account level via Organizations | Low | Enables cost attribution and OU-level tag policies later |
| `change_management_parameters` | Records who requested the account and why; stored in AFT DynamoDB as audit history | Low | Mandatory fields: `change_requested_by`, `change_reason` |
| Re-invoke customizations | `aft-invoke-customizations` Step Function lets you re-run global + account customizations on existing accounts without re-vending | Low to trigger | Filter by account ID, OU, or tag; critical for applying security changes to all existing accounts |
| account-provisioning-customizations | Step Functions state machine that runs BEFORE account creation; integrates with external CMDB, ServiceNow, IPAM | High | Skip unless you have pre-provisioning external system integration requirements; see Anti-Features |

### Control Tower Controls (Beyond Mandatory)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Strongly recommended detective controls | ~30 controls covering MFA on root, S3 public access, EBS encryption, etc. — visible on CT dashboard | Low per control | Enable per OU via CT console or `aws-control-tower-controls-terraform` module |
| Elective preventive controls | Additional SCPs e.g., deny root account usage, deny certain regions, deny public S3 ACLs | Low per control | Apply selectively to OUs as you understand workload needs |
| Proactive controls (CloudFormation hooks) | Block non-compliant resources at CloudFormation deploy time, before they exist | Medium | Requires CloudFormation usage; less relevant if workloads use Terraform |
| Region deny guardrail | SCP that restricts all activity to specified regions; useful for data residency | Low | Can be applied per OU |
| AFT feature flag: delete default VPCs | `aft_feature_delete_default_vpcs_enabled = true` removes the default VPC in every vended account in every region | Low (one flag) | Strong security posture; workloads must provision explicit VPCs |
| AFT feature flag: CloudTrail data events | `aft_feature_cloudtrail_data_events = true` enables S3 and Lambda data plane logging org-wide | Low | Significant cost at scale; evaluate before enabling |

### Networking (Deferred but Architectural)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Shared VPC via RAM (Resource Access Manager) | Share subnets from a networking account into workload accounts; workloads don't manage their own VPCs | High | Requires a dedicated networking account; correct for 10+ account orgs; skip for 6-account greenfield |
| Transit Gateway hub-and-spoke | Central routing between VPCs across accounts; enables shared services and egress routing | High | Share via RAM; correct pattern when accounts need to talk to each other or shared services |
| Per-account VPC (current scope) | Each vended account gets its own VPC via global or account customizations Terraform | Medium | Simpler for small orgs; each account is isolated; appropriate for chain-vote at this scale |

### IAM Identity Center Patterns

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Permission sets per role type | Standard PS for dev/read-only, staging/deploy, prod/break-glass; applied per account via CT | Medium | Not created by AFT by default; must add to global or account customizations |
| SSO Group → Account assignments | Federate IdP groups to CT-managed permission sets across all accounts | Medium | CT creates the `AWSAccountFactory` PS; others are custom work |

---

## Anti-Features

Things that sound useful but cause problems for a greenfield 6-account deployment at this stage.

### Over-Engineering Guardrails Early

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom SCPs on day 1 | SCPs can block legitimate workload operations in ways that are opaque to app developers; CT's mandatory SCPs are already substantial | Accept CT mandatory + strongly-recommended defaults; add custom SCPs per workload only when a concrete compliance requirement surfaces |
| Enabling all elective controls at once | ~300+ elective controls; many conflict with development workflows (e.g., blocking VPC internet gateways); enabling in bulk causes immediate drift alerts that obscure real issues | Enable elective controls one OU at a time, after you understand what each workload actually does |
| Proactive controls (CFN hooks) before Terraform is stable | Proactive controls fire on CloudFormation; Terraform-provisioned resources bypass them entirely; creates a false sense of coverage | Implement proactive controls only if you adopt CloudFormation for workload resources; irrelevant for Terraform-only workloads |

### AFT Complexity Traps

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| account-provisioning-customizations for simple pre-work | This layer requires Step Functions state machine authoring; AWS explicitly warns it's for advanced users | Put pre-provisioning logic in global customizations using bash/Python scripts, which run after account creation |
| Separate AFT management account (dedicated) | Adds a 7th account to manage and reason about; not necessary for small orgs | Use the CT management account as the AFT management account; acceptable for < 20 accounts |
| Modifying `control_tower_parameters` post-provisioning | AccountEmail, AccountName, SSOUser* fields are locked after first provision; attempting to change them fails silently or errors | Treat these as immutable; use `custom_fields` for anything you want to update later |
| Git-based VCS provider other than CodeCommit/GitHub/GitLab | AFT supports CodeCommit, GitHub, GitLab, Bitbucket; each has slightly different webhook behavior | Pick one VCS provider for all 4 AFT repos; don't mix providers |
| Running AFT with Terraform OSS AND a non-overridden distribution | AFT default `aft_tf_distribution = "oss"` assumes standard Terraform binary; OpenTofu requires overriding to `"TF"` and providing the binary path | Set `aft_tf_distribution = "TF"` and configure OpenTofu as the Terraform distribution at deploy time |

### Structural Mistakes

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Enrolling existing management account as a workload | CT management account has special status; it is exempt from most controls and cannot be moved to a workload OU | Leave management account in Root; provision all chain-vote accounts as new AFT-vended accounts |
| Creating OUs before registering parent OUs | CT requires parent OUs to be registered before child OUs can be registered or have accounts enrolled | Register Root → register workload-level OUs → create and register environment-level OUs |
| Naming OUs without OU ID in ManagedOrganizationalUnit for nested OUs | Level-1 OUs (direct children of Root) can use name-only; level-2+ OUs MUST use `OUName (ou-id)` format | Use `"chain-vote-ai-dev (ou-xxxx)"` format for the nested environment OUs |
| Assuming Config is free at CT scale | CT deploys Config recorders in every governed region for every account; at 6 accounts × 1 region × ~360 days, this is manageable but not zero | Budget $2-5/account/month for Config alone; track with Cost Explorer tags |

---

## Feature Dependencies

```
Control Tower landing zone deployed
  → Security OU exists with Log Archive + Audit accounts
  → IAM Identity Center enabled
  → Management account has AWSControlTowerAdmin role

Register workload OUs (chain-vote-ai, chain-vote-voting)
  → Requires: CT landing zone deployed
  → Enables: account enrollment in those OUs

Register nested environment OUs (dev, staging, prod under each workload OU)
  → Requires: parent workload OU registered
  → Enables: ManagedOrganizationalUnit = "chain-vote-ai-dev (ou-xxxx)" in AFT account requests

AFT module deployed
  → Requires: CT deployed, 4 Git repos initialized, AFT management account
  → Creates: CodePipeline, Lambda, DynamoDB, Step Functions, S3 state in AFT management account
  → Enables: account vending via git push to aft-account-request

Account request files committed (6 accounts)
  → Requires: AFT deployed, nested OUs registered and OU IDs known
  → Triggers: ct-aft-account-request CodePipeline → CT Account Factory → CT baselines account
  → Then: AFT account-specific pipeline runs global customizations → account customizations

Global customizations
  → Runs after each account vend and re-invoke
  → Should idempotent Terraform; assume it runs multiple times

Account customizations
  → Runs after global customizations
  → Keyed by account_customizations_name in account-request file
```

---

## MVP Recommendation

For the chain-vote greenfield deployment, build in this order:

**Must have (blocks everything else):**
1. CT landing zone with Security OU, Log Archive account, Audit account
2. IAM Identity Center enabled and CT configured
3. Workload OUs registered: `chain-vote-ai`, `chain-vote-voting`
4. Nested environment OUs registered: `dev`, `staging`, `prod` under each
5. AFT module deployed with OpenTofu (`aft_tf_distribution = "TF"`)
6. 4 AFT Git repos initialized (even if mostly empty)
7. 6 account-request files, one per account, committed to `aft-account-request`

**Enable immediately (free governance value):**
8. `aft_feature_delete_default_vpcs_enabled = true` — no cost, strong hygiene
9. Account tags: `Environment`, `Workload`, `Owner`, `CostCenter`
10. `change_management_parameters` on every account-request

**Defer (adds complexity, not blocking):**
- Global customizations: start empty, add IAM roles and Security Hub later
- Account customizations: add after workloads are running and you know what they need
- Elective/strongly-recommended CT controls: add one OU at a time post-go-live
- Transit Gateway / shared VPC: revisit at 10+ accounts or when cross-account traffic is needed
- CloudTrail data events feature flag: evaluate cost before enabling
- Custom SCPs: only when a concrete compliance requirement is identified

---

## Sources

- AWS Control Tower User Guide — https://docs.aws.amazon.com/controltower/latest/userguide/ (HIGH confidence, Context7)
- AFT Overview — https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html (HIGH confidence)
- AFT Provision Account — https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html (HIGH confidence)
- AFT Customization Options — https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html (HIGH confidence)
- AFT Provisioning Framework — https://docs.aws.amazon.com/controltower/latest/userguide/aft-provisioning-framework.html (HIGH confidence)
- AFT Feature Options — https://docs.aws.amazon.com/controltower/latest/userguide/aft-feature-options.html (HIGH confidence)
- AFT Architecture — https://docs.aws.amazon.com/controltower/latest/userguide/aft-architecture.html (HIGH confidence)
- CT Nested OUs and Controls — https://docs.aws.amazon.com/controltower/latest/userguide/nested-ous.html (HIGH confidence)
- CT Limitations and Quotas — https://docs.aws.amazon.com/controltower/latest/userguide/limits.html (HIGH confidence)
- Enroll Existing Account — https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html (HIGH confidence)
- AFT GitHub module (aws-ia) — https://github.com/aws-ia/terraform-aws-control_tower_account_factory (MEDIUM confidence)
- Rackspace AFT Customizations — https://www.rackspace.com/blog/scaling-landing-zone-customizations-on-aws (MEDIUM confidence)
- GlobalLogic Landing Zone pitfalls — https://www.globallogic.com/insights/blogs/deploying-a-landing-zone-with-aws-control-tower-part-2/ (MEDIUM confidence)
