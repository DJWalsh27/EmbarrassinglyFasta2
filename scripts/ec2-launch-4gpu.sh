#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"

STATE_FILE="${EC2_STATE_FILE:-$ROOT/manifests/ec2.state}"
NAME_TAG="${EC2_INSTANCE_TAG_NAME:-embfasta2-gpu}"
KEY_NAME="${EC2_KEY_NAME:-my-ec2-key}"
VOLUME_GB="${EC2_ROOT_GB:-1024}"
CANDIDATES="${EC2_4GPU_CANDIDATES:-g4dn.12xlarge g5.12xlarge g6.12xlarge p3.8xlarge}"

# Ubuntu 22.04 AMI via SSM (stable)
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

# Security group (reuse or create)
SG_ID="${EC2_SECURITY_GROUP_ID:-}"
if [[ -z "$SG_ID" ]]; then
  SG_NAME="${NAME_TAG}-sg"
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

  # Allow SSH from current IP (or override via EC2_SSH_CIDR)
  MYIP="${EC2_SSH_CIDR:-$(curl -s https://checkip.amazonaws.com)/32}"
  aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MYIP" \
    >/dev/null 2>&1 || true
fi

# Helper: get latest spot price for an instance type (Linux/UNIX)
spot_price() {
  local itype="$1"
  aws ec2 describe-spot-price-history \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --instance-types "$itype" \
    --product-descriptions "Linux/UNIX" \
    --start-time "$(date -u -v-6H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --max-items 1 \
    --query "SpotPriceHistory[0].SpotPrice" \
    --output text 2>/dev/null || echo "None"
}

# Sort candidates by spot price (best effort)
declare -a priced=()
for it in $CANDIDATES; do
  p="$(spot_price "$it")"
  if [[ "$p" != "None" && "$p" != "null" && "$p" != "NoneType" ]]; then
    priced+=("$p $it")
  fi
done

# If we got prices, sort by numeric price; else just use candidates order
if [[ ${#priced[@]} -gt 0 ]]; then
  mapfile -t ORDERED < <(printf "%s\n" "${priced[@]}" | sort -n | awk '{print $2}')
else
  mapfile -t ORDERED < <(printf "%s\n" $CANDIDATES)
fi

echo "Launch plan (Spot-first, 4 GPUs):"
echo "  Region:   $AWS_REGION"
echo "  Profile:  $AWS_PROFILE"
echo "  AMI:      $AMI_ID"
echo "  Subnet:   $SUBNET_ID"
echo "  SG:       $SG_ID"
echo "  Root:     ${VOLUME_GB}GB gp3"
echo "  Candidates (ordered): ${ORDERED[*]}"
echo

run_instance() {
  local market="$1" itype="$2"
  local market_args=()

  if [[ "$market" == "spot" ]]; then
    market_args=(--instance-market-options "MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}")
  fi

  aws ec2 run-instances \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --image-id "$AMI_ID" \
    --instance-type "$itype" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    "${market_args[@]}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$VOLUME_GB,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG},{Key=Project,Value=EmbarrassinglyFasta2},{Key=Market,Value=$market},{Key=GpuCount,Value=4}]" \
    --query "Instances[0].InstanceId" --output text
}

# Try Spot first (cheapest spot price ordering); on failure, try next type.
IID=""
CHOSEN_TYPE=""
CHOSEN_MARKET=""

echo "Trying Spot..."
for it in "${ORDERED[@]}"; do
  echo "  -> spot $it"
  set +e
  out="$(run_instance spot "$it" 2>&1)"
  ec=$?
  set -e
  if [[ $ec -eq 0 && "$out" =~ ^i- ]]; then
    IID="$out"; CHOSEN_TYPE="$it"; CHOSEN_MARKET="spot"
    break
  else
    echo "     spot failed for $it: $(echo "$out" | head -n 1)"
  fi
done

# If Spot failed entirely, fall back to On-Demand, cheapest-first using same ordering.
if [[ -z "$IID" ]]; then
  echo
  echo "Spot not available/fulfilled. Falling back to On-Demand..."
  for it in "${ORDERED[@]}"; do
    echo "  -> on-demand $it"
    set +e
    out="$(run_instance on-demand "$it" 2>&1)"
    ec=$?
    set -e
    if [[ $ec -eq 0 && "$out" =~ ^i- ]]; then
      IID="$out"; CHOSEN_TYPE="$it"; CHOSEN_MARKET="on-demand"
      break
    else
      echo "     on-demand failed for $it: $(echo "$out" | head -n 1)"
    fi
  done
fi

if [[ -z "$IID" ]]; then
  echo "ERROR: Could not launch any 4-GPU instance (spot or on-demand)." >&2
  exit 1
fi

echo
echo "$IID" > "$STATE_FILE"
echo "Launched: $IID"
echo "  InstanceType: $CHOSEN_TYPE"
echo "  Market:       $CHOSEN_MARKET"
echo "  Saved state:  $STATE_FILE"

echo "Waiting for running..."
aws ec2 wait instance-running --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$IID"

DNS="$(aws ec2 describe-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].PublicDnsName" --output text)"

echo "Public DNS: $DNS"
echo "SSH:"
echo "  ssh -i ${EC2_SSH_KEY_PATH:-~/.ssh/my-ec2-key} ${EC2_DEFAULT_USER:-ubuntu}@${DNS}"
