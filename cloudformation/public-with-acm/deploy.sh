#!/bin/bash
set -e

# ------------------------------
# Parameters
# ------------------------------
# Note: These values override the CloudFormation template defaults when deploying.
# Passing --parameter-overrides ensures these values are used instead of the template defaults.
STACK_NAME="achusec-public-s3-static-website"
TEMPLATE_FILE="template.yaml"
BUCKET_NAME="achusec-public-s3-static-website-us-east-1"

# ------------------------------
# Deploy CloudFormation Stack
# ------------------------------
echo "Deploying CloudFormation stack: $STACK_NAME..."
aws cloudformation deploy \
  --stack-name $STACK_NAME \
  --template-file $TEMPLATE_FILE \
  --parameter-overrides BucketName=$BUCKET_NAME \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo "Stack deployed."

# ------------------------------
# Retrieve Stack Outputs
# ------------------------------
# Get the S3 bucket name and CloudFront distribution domain from stack outputs
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
# CloudFront distributions can take some time to propagate.
# This sleep ensures the distribution is ready before uploading content.
echo "Waiting 30 seconds for CloudFront distribution to propagate..."
sleep 30

# ------------------------------
# Upload index.html to S3
# ------------------------------
# Upload the index.html file to the public S3 bucket
echo "Uploading index.html to S3 bucket: $BUCKET_NAME_OUTPUT..."
aws s3 cp index.html s3://$BUCKET_NAME_OUTPUT/

# ------------------------------
# Deployment Complete
# ------------------------------
echo "Deployment complete!"
echo "CloudFront URL: https://$CLOUDFRONT_DOMAIN"
