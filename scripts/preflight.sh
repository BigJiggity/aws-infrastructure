#!/usr/bin/env bash
set -euo pipefail

# Pre-flight validation script for AWS Control Tower enrollment.
# Checks for blockers before deploying CT landing zone.
# READ-ONLY — never mutates any AWS resources.

# ---------------------------------------------------------------------------
# ANSI color codes
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
BLOCKERS=0

pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  BLOCKERS=$((BLOCKERS + 1))
}

info() {
  echo -e "${YELLOW}[INFO]${NC} $*"
}

# ---------------------------------------------------------------------------
# Check 1 — AWS Config recorders (per D-08)
# Control Tower manages its own Config recorder. Pre-existing recorders in the
# management account will conflict with CT enrollment.
# ---------------------------------------------------------------------------
echo ""
echo "=== Check 1: AWS Config recorders ==="
RECORDERS=$(aws configservice describe-configuration-recorders \
  --query 'ConfigurationRecorders[*].name' \
  --output text 2>/dev/null || true)

if [[ -n "${RECORDERS}" && "${RECORDERS}" != "None" ]]; then
  fail "Existing AWS Config recorders found: ${RECORDERS}"
  echo "  Control Tower requires no pre-existing Config recorders in the management account."
  echo "  Remediation:"
  for recorder in ${RECORDERS}; do
    echo "    aws configservice stop-configuration-recorder --configuration-recorder-name ${recorder}"
    echo "    aws configservice delete-delivery-channel --delivery-channel-name ${recorder}"
    echo "    aws configservice delete-configuration-recorder --configuration-recorder-name ${recorder}"
  done
else
  pass "No AWS Config recorders found in management account."
fi

# ---------------------------------------------------------------------------
# Check 2 — Conflicting SCPs (per D-08)
# Any SCP attached to the root that explicitly Denies CT-related services will
# block the CT enrollment. Check for Deny statements covering key CT APIs.
# ---------------------------------------------------------------------------
echo ""
echo "=== Check 2: Conflicting SCPs ==="

CT_CONFLICT_FOUND=0

if ! command -v jq &>/dev/null; then
  info "jq is not installed — cannot parse SCP content. Manual inspection required."
  info "Check that no SCP attached to the ORG root Denies: controltower:*, cloudformation:*, config:*, cloudtrail:*"
else
  POLICIES=$(aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[*].{Id:Id,Name:Name}' \
    --output json 2>/dev/null || echo "[]")

  ORG_ROOT_ID=$(aws organizations list-roots \
    --query 'Roots[0].Id' \
    --output text 2>/dev/null || echo "")

  if [[ -z "${ORG_ROOT_ID}" || "${ORG_ROOT_ID}" == "None" ]]; then
    info "Could not retrieve Organizations root ID — skipping SCP check."
  else
    POLICY_COUNT=$(echo "${POLICIES}" | jq 'length')

    for i in $(seq 0 $((POLICY_COUNT - 1))); do
      POLICY_ID=$(echo "${POLICIES}" | jq -r ".[${i}].Id")
      POLICY_NAME=$(echo "${POLICIES}" | jq -r ".[${i}].Name")

      # Skip the AWS-managed FullAWSAccess policy
      if [[ "${POLICY_NAME}" == "FullAWSAccess" ]]; then
        continue
      fi

      # Check if this SCP is attached to the root
      TARGETS=$(aws organizations list-targets-for-policy \
        --policy-id "${POLICY_ID}" \
        --query 'Targets[*].TargetId' \
        --output json 2>/dev/null || echo "[]")

      IS_ROOT_ATTACHED=$(echo "${TARGETS}" | jq --arg root "${ORG_ROOT_ID}" \
        'map(select(. == $root)) | length > 0')

      if [[ "${IS_ROOT_ATTACHED}" == "true" ]]; then
        # Inspect SCP content for Deny statements on CT-related services
        CONTENT=$(aws organizations describe-policy \
          --policy-id "${POLICY_ID}" \
          --query 'Policy.Content' \
          --output text 2>/dev/null || echo "{}")

        CONFLICTING=$(echo "${CONTENT}" | jq -r '
          .Statement[]?
          | select(.Effect == "Deny")
          | .Action
          | if type == "array" then .[] else . end
          | select(
              test("^controltower:\\*") or
              test("^cloudformation:\\*") or
              test("^config:\\*") or
              test("^cloudtrail:\\*")
            )
        ' 2>/dev/null || true)

        if [[ -n "${CONFLICTING}" ]]; then
          fail "SCP '${POLICY_NAME}' (${POLICY_ID}) is attached to root and Denies CT-required actions: ${CONFLICTING}"
          echo "  Remediation: Detach or update the SCP before CT setup."
          echo "  Control Tower requires FullAWSAccess at the org root."
          echo "    aws organizations detach-policy --policy-id ${POLICY_ID} --target-id ${ORG_ROOT_ID}"
          CT_CONFLICT_FOUND=1
        fi
      fi
    done

    if [[ "${CT_CONFLICT_FOUND}" -eq 0 ]]; then
      pass "No conflicting SCPs found attached to the org root."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Check 3 — IAM role conflicts (per D-08)
# CT creates and owns specific IAM roles. Pre-existing roles with wrong trust
# policies or permissions will cause CT enrollment to fail.
# ---------------------------------------------------------------------------
echo ""
echo "=== Check 3: IAM role conflicts ==="

# Check AWSControlTowerExecution role
CT_EXEC_RESULT=$(aws iam get-role --role-name AWSControlTowerExecution \
  --output json 2>/dev/null || echo "NOT_FOUND")

if [[ "${CT_EXEC_RESULT}" == "NOT_FOUND" ]]; then
  pass "AWSControlTowerExecution role does not exist — CT will create it."
else
  # Role exists — verify trust policy and managed policies
  TRUST=$(echo "${CT_EXEC_RESULT}" | jq -r \
    '.Role.AssumeRolePolicyDocument.Statement[]?.Principal | values | tostring' 2>/dev/null || echo "")
  MGMT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

  ATTACHED=$(aws iam list-attached-role-policies \
    --role-name AWSControlTowerExecution \
    --query 'AttachedPolicies[*].PolicyName' \
    --output json 2>/dev/null || echo "[]")

  HAS_ADMIN=$(echo "${ATTACHED}" | jq 'map(select(. == "AdministratorAccess")) | length > 0')

  if [[ "${HAS_ADMIN}" == "true" ]] && echo "${TRUST}" | grep -q "${MGMT_ACCOUNT}"; then
    pass "AWSControlTowerExecution role exists with correct trust and AdministratorAccess."
  else
    fail "AWSControlTowerExecution role exists but has unexpected trust policy or missing AdministratorAccess."
    echo "  Remediation: Delete and let CT recreate:"
    echo "    aws iam delete-role --role-name AWSControlTowerExecution"
  fi
fi

# Check other CT-managed roles that must not pre-exist
CT_MANAGED_ROLES=(
  "AWSControlTowerAdmin"
  "AWSControlTowerCloudTrailRole"
  "AWSControlTowerConfigRecorderRole"
)

for role in "${CT_MANAGED_ROLES[@]}"; do
  EXISTS=$(aws iam get-role --role-name "${role}" --output json 2>/dev/null || echo "NOT_FOUND")
  if [[ "${EXISTS}" == "NOT_FOUND" ]]; then
    pass "Role ${role} does not exist — expected."
  else
    fail "CT-managed role '${role}' already exists. CT will fail to create it during enrollment."
    echo "  Remediation:"
    echo "    aws iam delete-role --role-name ${role}"
  fi
done

# ---------------------------------------------------------------------------
# Check 4 — Organizations trusted access (per D-08)
# CT requires Organizations trusted access to be enabled for specific service
# principals before it can operate across the org.
# ---------------------------------------------------------------------------
echo ""
echo "=== Check 4: Organizations trusted access ==="

ENABLED_PRINCIPALS=$(aws organizations list-aws-service-access-for-organization \
  --query 'EnabledServicePrincipals[*].ServicePrincipal' \
  --output json 2>/dev/null || echo "[]")

REQUIRED_PRINCIPALS=(
  "controltower.amazonaws.com"
  "config.amazonaws.com"
  "cloudtrail.amazonaws.com"
  "sso.amazonaws.com"
)

TRUSTED_ACCESS_OK=1

for principal in "${REQUIRED_PRINCIPALS[@]}"; do
  IS_ENABLED=$(echo "${ENABLED_PRINCIPALS}" | jq \
    --arg p "${principal}" 'map(select(. == $p)) | length > 0')

  if [[ "${IS_ENABLED}" == "true" ]]; then
    pass "Trusted access enabled for ${principal}"
  else
    fail "Trusted access NOT enabled for ${principal}"
    echo "  Remediation:"
    echo "    aws organizations enable-aws-service-access --service-principal ${principal}"
    TRUSTED_ACCESS_OK=0
  fi
done

# ---------------------------------------------------------------------------
# Check 5 — CloudTrail conflicts (per D-08)
# CT creates a mandatory multi-region organization trail. Pre-existing multi-region
# trails in us-east-1 will conflict with CT enrollment.
# ---------------------------------------------------------------------------
echo ""
echo "=== Check 5: CloudTrail multi-region trail conflicts ==="

TRAILS=$(aws cloudtrail describe-trails \
  --include-shadow-trails false \
  --query 'trailList[*].{Name:Name,IsMultiRegionTrail:IsMultiRegionTrail,HomeRegion:HomeRegion}' \
  --output json 2>/dev/null || echo "[]")

CONFLICTING_TRAILS=$(echo "${TRAILS}" | jq -r \
  '.[] | select(.IsMultiRegionTrail == true and .HomeRegion == "us-east-1") | .Name' 2>/dev/null || true)

if [[ -n "${CONFLICTING_TRAILS}" ]]; then
  for trail in ${CONFLICTING_TRAILS}; do
    fail "Multi-region CloudTrail '${trail}' (HomeRegion: us-east-1) conflicts with CT mandatory trail."
    echo "  CT creates its own mandatory multi-region trail. Disable or delete before enrolling:"
    echo "    aws cloudtrail delete-trail --name ${trail}"
  done
else
  pass "No conflicting multi-region CloudTrail trails found in us-east-1."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Pre-flight Check Summary ==="

if [[ "${BLOCKERS}" -gt 0 ]]; then
  echo -e "${RED}FAILED: ${BLOCKERS} blocker(s) found. Resolve all issues above before deploying Control Tower.${NC}"
  exit 1
else
  echo -e "${GREEN}PASSED: All checks passed. Ready to deploy Control Tower landing zone.${NC}"
fi
