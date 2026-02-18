#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"

STATE_FILE="${EC2_STATE_FILE:-$ROOT/manifests/ec2.state}"
NAME_TAG="${EC2_INSTANCE_TAG_NAME:-embfasta2-gpu}"
KEY_NAME="${EC2_KEY_NAME:-my-ec2-key}"
INSTANCE_TYPE="${EC2_INSTANCE_TYPE_DEFAULT:-g5.2xlarge}"
VOLUME_GB="${EC2_ROOT_GB:-500}"

# Default: Ubuntu 22.04 AMI via SSM (stable)
AMI_ID="${EC2_AMI_ID:-}"
if [[ -z "$AMI_ID" ]]; then
  AMI_ID="$(aws ssm get-parameter \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query "Parameter.Value" --output text)"
fi

# Default VPC + default subnet
VPC_ID="${EC2_VPC_ID:-}"
if [[ -z "$VPC_ID" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" --output text)"
fi

SUBNET_ID="${EC2_SUBNET_ID:-}"
if [[ -z "$SUBNET_ID" ]]; then
  SUBNET_ID="$(aws ec2 describe-subnets \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
    --query "Subnets[0].SubnetId" --output text)"
fi

# Security group: create if not provided
SG_ID="${EC2_SECURITY_GROUP_ID:-}"
if [[ -z "$SG_ID" ]]; then
  SG_NAME="${NAME_TAG}-sg"
  # reuse if exists
  SG_ID="$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)"
  if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    SG_ID="$(aws ec2 create-security-group \
      --region "$AWS_REGION" --profile "$AWS_PROFILE" \
      --group-name "$SG_NAME" \
      --description "SSH access for $NAME_TAG" \
      --vpc-id "$VPC_ID" \
      --query GroupId --output text)"
  fi

  # Allow SSH from current IP unless EC2_SSH_CIDR is set
  MYIP="${EC2_SSH_CIDR:-$(curl -s https://checkip.amazonaws.com)/32}"

  # Add rule (ignore error if already exists)
  aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MYIP" \
    >/dev/null 2>&1 || true
fi

echo "Launching EC2..."
echo "  Name tag:     $NAME_TAG"
echo "  Region:       $AWS_REGION"
echo "  Profile:      $AWS_PROFILE"
echo "  AMI:          $AMI_ID"
echo "  Type:         $INSTANCE_TYPE"
echo "  KeyPair:      $KEY_NAME"
echo "  SG:           $SG_ID"
echo "  Subnet:       $SUBNET_ID"
echo "  Root volume:  ${VOLUME_GB}GB gp3"

INSTANCE_ID="$(aws ec2 run-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$VOLUME_GB,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG},{Key=Project,Value=EmbarrassinglyFasta2}]" \
  --query "Instances[0].InstanceId" --output text)"

echo "$INSTANCE_ID" > "$STATE_FILE"
echo "Instance ID: $INSTANCE_ID (saved to $STATE_FILE)"

echo "Waiting for running..."
aws ec2 wait instance-running --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$INSTANCE_ID"

DNS="$(aws ec2 describe-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicDnsName" --output text)"

IP="$(aws ec2 describe-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"

echo "Public DNS: $DNS"
echo "Public IP:  $IP"
echo
echo "SSH:"
echo "  ssh -i ${EC2_SSH_KEY_PATH:-~/.ssh/my-ec2-key} ${EC2_DEFAULT_USER:-ubuntu}@${DNS}"
