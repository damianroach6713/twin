#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-twin}"

echo "Deploying ${PROJECT_NAME} to ${ENVIRONMENT} ..."

# Move to project root
cd "$(dirname "$0")/.."

# 1. Build Lambda package
echo "Building Lambda package..."
cd backend
uv run deploy.py
cd ..

# 2. Terraform workspace & apply
cd terraform

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="${DEFAULT_AWS_REGION:-us-east-1}"

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

if [ "${ENVIRONMENT}" = "prod" ]; then
  terraform apply \
    -var-file="prod.tfvars" \
    -var="project_name=${PROJECT_NAME}" \
    -var="environment=${ENVIRONMENT}" \
    -auto-approve
else
  terraform apply \
    -var="project_name=${PROJECT_NAME}" \
    -var="environment=${ENVIRONMENT}" \
    -auto-approve
fi

API_URL="$(terraform output -raw api_gateway_url)"
FRONTEND_BUCKET="$(terraform output -raw s3_frontend_bucket)"

CUSTOM_URL=""
if terraform output -raw custom_domain_url >/tmp/custom_domain_url.txt 2>/dev/null; then
  CUSTOM_URL="$(cat /tmp/custom_domain_url.txt)"
fi

# 3. Build + deploy frontend
cd ../frontend

echo "Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=${API_URL}" > .env.production

npm install
npm run build

aws s3 sync ./out "s3://${FRONTEND_BUCKET}/" --delete

cd ..

# 4. Final summary
CF_URL="$(terraform -chdir=terraform output -raw cloudfront_url)"

echo "Deployment complete!"
echo "CloudFront URL : ${CF_URL}"

if [ -n "${CUSTOM_URL}" ]; then
  echo "Custom domain  : ${CUSTOM_URL}"
fi

echo "API Gateway    : ${API_URL}"