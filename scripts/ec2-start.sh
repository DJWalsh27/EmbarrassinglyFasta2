#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"
IID="$("$ROOT/scripts/ec2-id.sh")"

aws ec2 start-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$IID" >/dev/null
aws ec2 wait instance-running --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$IID"
"$ROOT/scripts/ec2-status.sh"
