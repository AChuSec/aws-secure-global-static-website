#!/bin/bash
set -e

# ------------------------------
# Delete Private S3 Static Website Stack
# ------------------------------
STACK_NAME="private-s3-static-website"

echo "WARNING: This will delete the CloudFormation stack '$STACK_NAME' and all associated resources."
read -p "Are you sure you want to proceed? [y/N]: " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
  echo "Aborting deletion."
  exit 0
fi

# Optional: Delete all objects in the private S3 bucket before stack deletion
echo "Fetching S3 bucket name from stack outputs..."
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
  --output text)

if [[ -n "$BUCKET_NAME" ]]; then
  echo "Deleting all objects in S3 bucket: $BUCKET_NAME..."
  aws s3 rm s3://$BUCKET_NAME --recursive || echo "Bucket empty or does not exist."
fi

# Delete the CloudFormation stack
echo "Deleting CloudFormation stack: $STACK_NAME..."
aws cloudformation delete-stack --stack-name $STACK_NAME

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

echo "Stack '$STACK_NAME' deleted successfully."
