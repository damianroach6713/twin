#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-twin}"

echo "Deploying ${PROJECT_NAME} to ${ENVIRONMENT} ..."

cd "$(dirname "$0")/.."

echo "Building Lambda package..."
cd backend
uv run deploy.py
cd ..

cd terraform

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-2}"

terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if terraform workspace list | grep -qE "^[* ]+${ENVIRONMENT}$"; then
  terraform workspace select "${ENVIRONMENT}"
else
  terraform workspace new "${ENVIRONMENT}"
fi

terraform apply \
  -var="project_name=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -auto-approve