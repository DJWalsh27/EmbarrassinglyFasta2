#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"
IID="$("$ROOT/scripts/ec2-id.sh")"

aws ec2 describe-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress,PublicDns:PublicDnsName,LaunchTime:LaunchTime,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table
