#!/bin/bash

# Script to set up AWS CodeBuild project for monthly multi-region AMI builds

set -e

echo "Setting up CodeBuild project for monthly multi-region AMI builds..."

# Check required environment variables
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Error: AWS_ACCOUNT_ID environment variable is required"
    echo "Run: export AWS_ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)"
    exit 1
fi

# Prompt for configuration
echo ""
echo "Enter the regions where you want to build AMIs (comma-separated):"
echo "Example: us-east-1,us-west-2,eu-west-1"
read -p "Regions: " BUILD_REGIONS

echo ""
echo "Enter additional regions to copy AMIs to (comma-separated, or leave blank):"
echo "Example: ap-southeast-1,eu-central-1"
read -p "Copy to regions (optional): " COPY_REGIONS

echo ""
echo "Enter your GitHub repository URL:"
echo "Example: https://github.com/yourorg/optix-appliance-iac.git"
read -p "GitHub URL: " GITHUB_URL

# Create S3 bucket for artifacts
BUCKET_NAME="optix-ami-build-artifacts-${AWS_ACCOUNT_ID}"
echo ""
echo "Creating S3 bucket for build artifacts: $BUCKET_NAME"
aws s3 mb s3://$BUCKET_NAME --region us-east-1 2>/dev/null || echo "Bucket already exists"

# Store configuration in Parameter Store
echo ""
echo "Storing configuration in AWS Systems Manager Parameter Store..."

aws ssm put-parameter \
    --name "/optix/build-regions" \
    --value "$BUILD_REGIONS" \
    --type "String" \
    --overwrite \
    --description "Regions where AMIs will be built"

if [ ! -z "$COPY_REGIONS" ]; then
    aws ssm put-parameter \
        --name "/optix/copy-to-regions" \
        --value "$COPY_REGIONS" \
        --type "String" \
        --overwrite \
        --description "Additional regions to copy AMIs to"
fi

# Store VPC and Subnet IDs for each region
IFS=',' read -ra REGIONS_ARRAY <<< "$BUILD_REGIONS"
for REGION in "${REGIONS_ARRAY[@]}"; do
    REGION=$(echo $REGION | xargs)  # Trim whitespace
    REGION_UNDERSCORE=${REGION//-/_}
    
    echo ""
    echo "Configuration for region: $REGION"
    read -p "Enter VPC ID for $REGION: " VPC_ID
    read -p "Enter Subnet ID for $REGION: " SUBNET_ID
    
    aws ssm put-parameter \
        --name "/optix/vpc-id-${REGION}" \
        --value "$VPC_ID" \
        --type "SecureString" \
        --overwrite \
        --description "VPC ID for $REGION"
    
    aws ssm put-parameter \
        --name "/optix/subnet-id-${REGION}" \
        --value "$SUBNET_ID" \
        --type "SecureString" \
        --overwrite \
        --description "Subnet ID for $REGION"
    
    # Set first region as default
    if [ -z "$DEFAULT_SET" ]; then
        aws ssm put-parameter \
            --name "/optix/vpc-id-default" \
            --value "$VPC_ID" \
            --type "SecureString" \
            --overwrite \
            --description "Default VPC ID"
        
        aws ssm put-parameter \
            --name "/optix/subnet-id-default" \
            --value "$SUBNET_ID" \
            --type "SecureString" \
            --overwrite \
            --description "Default Subnet ID"
        
        DEFAULT_SET=1
    fi
done

# Create IAM role for CodeBuild
echo ""
echo "Creating IAM role for CodeBuild..."

cat > /tmp/codebuild-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name codebuild-optix-ami-role \
    --assume-role-policy-document file:///tmp/codebuild-trust-policy.json \
    2>/dev/null || echo "Role already exists"

# Attach policies to the role
cat > /tmp/codebuild-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetBucketLocation",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ec2:*",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name codebuild-optix-ami-role \
    --policy-name codebuild-optix-ami-policy \
    --policy-document file:///tmp/codebuild-policy.json

# Update CodeBuild project JSON with actual values
sed -i.bak \
    -e "s|YOUR_ORG/optix-appliance-iac|${GITHUB_URL#https://github.com/}|" \
    -e "s|optix-ami-build-artifacts|$BUCKET_NAME|" \
    -e "s|ACCOUNT_ID|$AWS_ACCOUNT_ID|" \
    codebuild-project.json

# Create CodeBuild project
echo ""
echo "Creating CodeBuild project..."
aws codebuild create-project --cli-input-json file://codebuild-project.json || \
    aws codebuild update-project --cli-input-json file://codebuild-project.json

# Create EventBridge rule for monthly schedule
echo ""
echo "Creating EventBridge rule for monthly schedule..."

aws events put-rule \
    --name optix-monthly-ami-build-schedule \
    --schedule-expression "cron(0 2 1 * ? *)" \
    --description "Trigger monthly AMI builds on the 1st of each month at 2 AM UTC" \
    --state ENABLED

# Create IAM role for EventBridge
cat > /tmp/eventbridge-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name eventbridge-codebuild-role \
    --assume-role-policy-document file:///tmp/eventbridge-trust-policy.json \
    2>/dev/null || echo "Role already exists"

cat > /tmp/eventbridge-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "codebuild:StartBuild",
      "Resource": "arn:aws:codebuild:*:${AWS_ACCOUNT_ID}:project/optix-monthly-ami-build"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name eventbridge-codebuild-role \
    --policy-name eventbridge-codebuild-policy \
    --policy-document file:///tmp/eventbridge-policy.json

# Add CodeBuild as target for EventBridge rule
aws events put-targets \
    --rule optix-monthly-ami-build-schedule \
    --targets "Id=1,Arn=arn:aws:codebuild:us-east-1:${AWS_ACCOUNT_ID}:project/optix-monthly-ami-build,RoleArn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/eventbridge-codebuild-role"

# Clean up temporary files
rm -f /tmp/codebuild-trust-policy.json /tmp/codebuild-policy.json
rm -f /tmp/eventbridge-trust-policy.json /tmp/eventbridge-policy.json

echo ""
echo "========================================="
echo "Setup complete!"
echo "========================================="
echo ""
echo "Monthly builds will run on the 1st of each month at 2 AM UTC"
echo "Building in regions: $BUILD_REGIONS"
if [ ! -z "$COPY_REGIONS" ]; then
    echo "Copying to regions: $COPY_REGIONS"
fi
echo ""
echo "To trigger a build manually, run:"
echo "aws codebuild start-build --project-name optix-monthly-ami-build"
echo ""
echo "To view build history:"
echo "aws codebuild batch-get-builds --ids \$(aws codebuild list-builds-for-project --project-name optix-monthly-ami-build --query 'ids' --output text)"