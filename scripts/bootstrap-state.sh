#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the S3 state bucket and DynamoDB lock table for OpenTofu/Terragrunt.
# This script is idempotent — safe to run multiple times.
# Must be run with management account credentials before any `tofu init` or
# `terragrunt run-all` that references the remote state backend.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="chain-vote-tofu-state-${ACCOUNT_ID}"
TABLE_NAME="chain-vote-tofu-locks"
REGION="us-east-1"

echo "=== State Backend Bootstrap ==="
echo "Account    : ${ACCOUNT_ID}"
echo "S3 Bucket  : ${BUCKET_NAME}"
echo "DynamoDB   : ${TABLE_NAME}"
echo "Region     : ${REGION}"
echo ""

# ---------------------------------------------------------------------------
# S3 bucket — create if it does not exist
# ---------------------------------------------------------------------------
echo "--- S3 Bucket ---"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "[INFO] Bucket ${BUCKET_NAME} already exists — skipping creation."
else
  echo "[INFO] Creating bucket ${BUCKET_NAME} in ${REGION}..."
  # NOTE: us-east-1 does NOT accept --create-bucket-configuration.
  # That flag is only valid for other regions. AWS will reject the call if used here.
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}"
  echo "[INFO] Bucket created."
fi

# Enable versioning (idempotent — safe to re-apply)
echo "[INFO] Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# Enable SSE-S3 encryption (idempotent — safe to re-apply)
echo "[INFO] Enabling SSE-S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

# Block all public access (idempotent — safe to re-apply)
echo "[INFO] Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "[INFO] S3 bucket configured successfully."
echo ""

# ---------------------------------------------------------------------------
# DynamoDB lock table — create if it does not exist
# ---------------------------------------------------------------------------
echo "--- DynamoDB Lock Table ---"

if aws dynamodb describe-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" &>/dev/null; then
  echo "[INFO] DynamoDB table ${TABLE_NAME} already exists — skipping creation."
else
  echo "[INFO] Creating DynamoDB table ${TABLE_NAME}..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "[INFO] Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}"

  echo "[INFO] DynamoDB table is ACTIVE."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== State Backend Bootstrap Complete ==="
echo "S3 Bucket : ${BUCKET_NAME}"
echo "DynamoDB  : ${TABLE_NAME}"
echo "Region    : ${REGION}"
echo ""
echo "Add to your environment or save these values:"
echo "  export TF_STATE_BUCKET=${BUCKET_NAME}"
echo "  export TF_STATE_LOCK_TABLE=${TABLE_NAME}"
