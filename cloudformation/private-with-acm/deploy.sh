#!/bin/bash
set -e

# ------------------------------
# Parameters
# ------------------------------
# Note: These values override the CloudFormation template defaults when deploying.
# Passing --parameter-overrides ensures these values are used instead of the template defaults.
STACK_NAME="private-s3-static-website"
TEMPLATE_FILE="template.yaml"
PARAMS_FILE="parameters.json"

# ------------------------------
# Deploy CloudFormation Stack
# ------------------------------
echo "Deploying CloudFormation stack: $STACK_NAME..."
aws cloudformation deploy \
  --stack-name $STACK_NAME \
  --template-file $TEMPLATE_FILE \
  --cli-input-json file://$PARAMS_FILE \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset
echo "Stack deployed."

# ------------------------------
# Retrieve Stack Outputs
# ------------------------------
# Get the private S3 bucket name and CloudFront distribution domain from stack outputs
BUCKET_NAME_OUTPUT=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
  --output text)

CLOUDFRONT_DOMAIN=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontURL'].OutputValue" \
  --output text)

# ------------------------------
# Wait for CloudFront to propagate
# ------------------------------
# CloudFront distributions take time to propagate. Sleep ensures the distribution is ready before uploading content.
echo "Waiting 30 seconds for CloudFront distribution to propagate..."
sleep 30

# ------------------------------
# Upload index.html to private S3 bucket
# ------------------------------
# Upload the index.html file via CloudFront origin access (OAC) to keep the bucket private
echo "Uploading index.html to private S3 bucket via CloudFront origin..."
aws s3 cp index.html s3://$BUCKET_NAME_OUTPUT/

# ------------------------------
# Deployment Complete
# ------------------------------
echo "Deployment complete!"
echo "CloudFront URL: https://$CLOUDFRONT_DOMAIN"
