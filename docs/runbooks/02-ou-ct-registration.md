# Runbook 02: Register OUs with AWS Control Tower

**Prerequisite:** `management/ou-structure/` has been applied (`terragrunt apply` exited 0).
**Prerequisite:** CT landing zone status is **Ready** (see Runbook 01).

---

## Why OUs Must Be Registered Separately from Creation

`aws_organizations_organizational_unit` creates OUs inside AWS Organizations, but Control Tower does not automatically govern new OUs. CT governance — SCPs, CloudTrail, Config rules, CloudFormation StackSets — only applies to OUs that have been explicitly enrolled via the CT baseline mechanism.

CT enforces the same parent-before-child constraint for registration that Organizations enforces for creation: a child OU cannot be registered with CT until its parent OU registration has reached `SUCCEEDED` status. Attempting to register a child before its parent will return `ConstraintViolationException`.

**Do NOT use `run-all apply` across `management/`.** Apply each unit individually from its own directory with `terragrunt apply`. All 8 OU resources are in one state file under `management/ou-structure/` and OpenTofu sequences them correctly in a single apply.

---

## Step 1: Capture OU IDs from Terragrunt Outputs

```bash
cd management/ou-structure

AI_PARENT_OU=$(terragrunt output -raw chain_vote_ai_ou_id)
VOTING_PARENT_OU=$(terragrunt output -raw chain_vote_voting_ou_id)
AI_DEV_OU=$(terragrunt output -raw chain_vote_ai_dev_ou_id)
AI_STAGING_OU=$(terragrunt output -raw chain_vote_ai_staging_ou_id)
AI_PROD_OU=$(terragrunt output -raw chain_vote_ai_prod_ou_id)
VOTING_DEV_OU=$(terragrunt output -raw chain_vote_voting_dev_ou_id)
VOTING_STAGING_OU=$(terragrunt output -raw chain_vote_voting_staging_ou_id)
VOTING_PROD_OU=$(terragrunt output -raw chain_vote_voting_prod_ou_id)

cd ../..
```

Verify the variables are populated before proceeding:

```bash
echo "AI parent:      ${AI_PARENT_OU}"
echo "Voting parent:  ${VOTING_PARENT_OU}"
echo "AI dev:         ${AI_DEV_OU}"
echo "AI staging:     ${AI_STAGING_OU}"
echo "AI prod:        ${AI_PROD_OU}"
echo "Voting dev:     ${VOTING_DEV_OU}"
echo "Voting staging: ${VOTING_STAGING_OU}"
echo "Voting prod:    ${VOTING_PROD_OU}"
```

Each value should be an OU ID in the form `ou-xxxx-xxxxxxxx`.

---

## Step 2: Confirm the Baseline ARN for Your Region

The `AWSControlTowerBaseline` ARN is region-specific. Confirm it before proceeding:

```bash
aws controltower list-baselines \
  --query 'baselines[?name==`AWSControlTowerBaseline`].{ARN:arn,Name:name}' \
  --output table
```

The ARN format is `arn:aws:controltower:us-east-1::baseline/AWSControlTowerBaseline`. Use the ARN returned by this command in all `enable-baseline` calls below.

---

## Step 3: Register Parent OUs (Strictly Sequential)

CT requires each registration to reach `SUCCEEDED` before the next registration is submitted. Do not batch parent OU registrations.

### Register chain-vote-ai

```bash
OPERATION_AI=$(aws controltower enable-baseline \
  --baseline-identifier arn:aws:controltower:us-east-1::baseline/AWSControlTowerBaseline \
  --baseline-version "1.0" \
  --target-identifier "${AI_PARENT_OU}" \
  --query 'operationIdentifier' \
  --output text)

echo "Operation ID: ${OPERATION_AI}"
```

Poll until `SUCCEEDED`:

```bash
aws controltower get-baseline-operation \
  --operation-identifier "${OPERATION_AI}" \
  --query 'baselineOperation.status' \
  --output text
```

**Do not proceed to the next step until this returns `SUCCEEDED`.**

### Register chain-vote-voting (after chain-vote-ai SUCCEEDED)

```bash
OPERATION_VOTING=$(aws controltower enable-baseline \
  --baseline-identifier arn:aws:controltower:us-east-1::baseline/AWSControlTowerBaseline \
  --baseline-version "1.0" \
  --target-identifier "${VOTING_PARENT_OU}" \
  --query 'operationIdentifier' \
  --output text)

echo "Operation ID: ${OPERATION_VOTING}"
```

Poll until `SUCCEEDED` before proceeding to child OU registration.

---

## Step 4: Register Child OUs (After Their Parent SUCCEEDED)

Once a parent OU registration is `SUCCEEDED`, register its children. Children of the same parent can be submitted in a loop, but submit one at a time and note each operation ID.

### chain-vote-ai children

Run this only after `chain-vote-ai` parent is `SUCCEEDED`:

```bash
for OU_ID in "${AI_DEV_OU}" "${AI_STAGING_OU}" "${AI_PROD_OU}"; do
  OP=$(aws controltower enable-baseline \
    --baseline-identifier arn:aws:controltower:us-east-1::baseline/AWSControlTowerBaseline \
    --baseline-version "1.0" \
    --target-identifier "${OU_ID}" \
    --query 'operationIdentifier' \
    --output text)
  echo "Submitted registration for ${OU_ID} — operation ID: ${OP}"
  echo "Wait for SUCCEEDED in CT console before next step"
  sleep 5
done
```

### chain-vote-voting children

Run this only after `chain-vote-voting` parent is `SUCCEEDED`:

```bash
for OU_ID in "${VOTING_DEV_OU}" "${VOTING_STAGING_OU}" "${VOTING_PROD_OU}"; do
  OP=$(aws controltower enable-baseline \
    --baseline-identifier arn:aws:controltower:us-east-1::baseline/AWSControlTowerBaseline \
    --baseline-version "1.0" \
    --target-identifier "${OU_ID}" \
    --query 'operationIdentifier' \
    --output text)
  echo "Submitted registration for ${OU_ID} — operation ID: ${OP}"
  echo "Wait for SUCCEEDED in CT console before next step"
  sleep 5
done
```

---

## Step 5: Verify Final Structure

After all 8 OUs show `SUCCEEDED`:

```bash
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

# Verify OU tree in Organizations
echo "=== Root children ==="
aws organizations list-organizational-units-for-parent \
  --parent-id "${ROOT_ID}" \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table

echo "=== chain-vote-ai children ==="
aws organizations list-organizational-units-for-parent \
  --parent-id "${AI_PARENT_OU}" \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table

echo "=== chain-vote-voting children ==="
aws organizations list-organizational-units-for-parent \
  --parent-id "${VOTING_PARENT_OU}" \
  --query 'OrganizationalUnits[*].{Name:Name,Id:Id}' \
  --output table

# Verify CT enrollment status
echo "=== CT baseline status for all enrolled OUs ==="
aws controltower list-enabled-baselines \
  --query 'enabledBaselines[*].{Target:targetIdentifier,Status:statusSummary.status}' \
  --output table
```

Expected output:
- Root children table shows `chain-vote-ai` and `chain-vote-voting`
- Each parent children table shows `dev`, `staging`, `prod`
- CT baseline status shows all 8 OU IDs with `SUCCEEDED`

---

## Troubleshooting

### Registration shows FAILED

Check CloudFormation StackSet operations in the management account:

```bash
aws cloudformation list-stack-set-operations \
  --stack-set-name AWSControlTowerBP-BASELINE-CONFIG \
  --query 'Summaries[?Status==`FAILED`]' \
  --output table
```

The most common cause is a pre-existing AWS Config recorder or delivery channel in a target account. Remediation: remove the conflicting Config recorder in the affected account, then re-submit `enable-baseline` for the failed OU.

### Registration stuck IN_PROGRESS for more than 20 minutes

Check the CT console for a "Setup in progress" banner — another CT operation may be running concurrently. CT does not support parallel baseline operations. Wait for the concurrent operation to complete, then poll again.

You can also check for active CT operations:

```bash
aws controltower list-baseline-operations \
  --query 'baselineOperations[?status==`IN_PROGRESS`]' \
  --output table
```

### Do NOT register these OUs

- **Root** — CT-managed automatically; re-registering will fail.
- **Security OU** — CT-managed automatically; contains Log Archive and Audit accounts.

Registering these will return an error from the CT API.
