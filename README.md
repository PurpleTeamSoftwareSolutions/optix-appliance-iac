# Optix Appliance IAC #
[CyberOptix](https://purpleteamsoftware.com/cyberoptix/) is a full featured vulnerability management platform for Red and Blue teams. The CyberOptix appliance is the client application designed to perform tasks during penetration tests and security audits using
Docker containers. This repository contains packer files and scripts to automate building OVA, AMI, and Azure images of the Optix Appliance.

# Step 1 ) #

## Download Packer and Set your environment variables ##

**_Download packer:_**

1) Download the proper Packer binary from https://www.packer.io/downloads.
2) Unzip the package into the `optix-appliance-iac` directory.


## On Windows OS ##
 
*_Set variables for the AMI:_*

1) setx AWS_ACCESS_KEY_ID "Your AWS Access Key ID"
2) setx AWS_SECRET_ACCESS_KEY "Your AWS Secret Key"
3) setx AWS_VPC_ID "The AWS VPC ID you are building the AMI in"
4) setx AWS_SUBNET_ID "The AWS Subnet ID you are building the AMI in"
5) setx AWS_INSTANCE_TYPE "The AWS instance type you will be using (e.g., t3.micro for x86_64)"
6) setx AWS_REGION "The AWS region to deploy the AMI"

*_Set variables for the AZURE Image:_*

1) setx AZURE_CLIENT_ID "Your Azure client id"
2) setx AZURE_CLIENT_SECRET "Your Azure client secret"
3) setx AZURE_SUBSCRIPTION_ID "Your Azure subscription id"
4) setx AZURE_TENANT_ID "Your Azure tenant id"
5) setx AZURE_LOCATION "The Azure location to keep the image"
6) setx AZURE_VM_SIZE "The default VM size"
7) setx AZURE_RESOURCE_GROUP_NAME "The Azure resource group name"

## On macOS or Linux ##

*_Set variables for the AMI:_*

1) export AWS_ACCESS_KEY_ID="Your AWS Access Key ID"
2) export AWS_SECRET_ACCESS_KEY="Your AWS Secret Key"
3) export AWS_VPC_ID="The AWS VPC ID you are building the AMI in"
4) export AWS_SUBNET_ID="The AWS Subnet ID you are building the AMI in"
5) export AWS_INSTANCE_TYPE="The AWS instance type you will be using (e.g., t3.micro for x86_64)"
6) export AWS_REGION="The AWS region to deploy the AMI"

*_Set variables for the AZURE Image:_*

1) export AZURE_CLIENT_ID="Your Azure client id"
2) export AZURE_CLIENT_SECRET="Your Azure client secret"
3) export AZURE_SUBSCRIPTION_ID="Your Azure subscription id"
4) export AZURE_TENANT_ID="Your Azure tenant id"
5) export AZURE_LOCATION="The Azure location to keep the image"
6) export AZURE_VM_SIZE="The default VM size"
7) export AZURE_RESOURCE_GROUP_NAME="The Azure resource group name"

# Step 2 ) #

## Executing the packer file: ##

*_To build AMIs:_*

**Ubuntu 24.04 (Noble):**
Run the following command - `packer build appliance/packer-file-AMI-ubuntu.json`

**Red Hat Enterprise Linux 9:**
Run the following command - `packer build appliance/packer-file-AMI-rhel9.json`

Note: RHEL 9 AMIs can be used with either hourly billing or BYOS (Bring Your Own Subscription). 
For BYOS, register the instance after launch using `sudo subscription-manager register`.

*_To build the AZURE Image:_*
Run the following command - `packer build scanner/packer-file-AZURE.json`

**_AMI Notes:_**

Your build system must have ssh access to the AMI to run the `provision.sh` script. The `packer-file.json` is configured to use a public address.
If this is unacceptable please modify the `packer-file.json` and change `associate_public_ip_address` to `false`.

**_Referances:_**
https://docs.microsoft.com/en-us/azure/virtual-machines/linux/build-image-with-packer#define-packer-template

# Step 3 ) #

Now you have a template to use to deploy the Optix Appliance image.

# Automated Monthly Multi-Region AMI Builds #

This repository includes AWS CodeBuild configuration for automated monthly AMI builds across multiple AWS regions.

## Features

- **Multi-Region Support**: Build AMIs in multiple regions simultaneously
- **Monthly Schedule**: Automatically runs on the 1st of each month at 2 AM UTC
- **Two AMI Variants**: Ubuntu 24.04 and RHEL 9 (supports both hourly billing and BYOS)
- **Region-Specific Configuration**: Different VPC/Subnet settings per region
- **Optional AMI Copying**: Copy AMIs to additional regions after building

## Setup Instructions

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. AWS account ID available

### Installation

1. **Set your AWS Account ID:**
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

2. **Run the setup script:**
```bash
cd aws-codebuild
chmod +x setup.sh
./setup.sh
```

3. **Follow the prompts to configure:**
   - Build regions (e.g., us-east-1,us-west-2,eu-west-1)
   - Optional copy-to regions for AMI replication
   - VPC and Subnet IDs for each build region
   - GitHub repository URL

The setup script will:
- Create an S3 bucket for build artifacts
- Store configuration in AWS Systems Manager Parameter Store
- Create IAM roles for CodeBuild and EventBridge
- Set up the CodeBuild project
- Configure EventBridge for monthly scheduling

## Manual Build Execution

To trigger a build manually:
```bash
aws codebuild start-build --project-name optix-monthly-ami-build
```

## Monitoring Builds

View build history:
```bash
aws codebuild batch-get-builds --ids $(aws codebuild list-builds-for-project \
  --project-name optix-monthly-ami-build --query 'ids' --output text)
```

View logs in CloudWatch:
- Log group: `/aws/codebuild/optix-monthly-ami-build`

## Configuration Management

All configuration is stored in AWS Systems Manager Parameter Store:
- `/optix/build-regions` - Regions where AMIs are built
- `/optix/copy-to-regions` - Additional regions for AMI copying
- `/optix/vpc-id-{region}` - VPC ID for each region
- `/optix/subnet-id-{region}` - Subnet ID for each region

To update configuration:
```bash
aws ssm put-parameter --name "/optix/build-regions" \
  --value "us-east-1,us-west-2,eu-west-1,ap-southeast-1" \
  --overwrite
```

## Build Output

- AMI IDs are displayed in the build logs
- Build artifacts are stored in S3: `optix-ami-build-artifacts-{account-id}`
- Both AMI types (Ubuntu and RHEL 9) are built in each specified region