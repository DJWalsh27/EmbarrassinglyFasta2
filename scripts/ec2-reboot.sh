#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"
IID="$("$ROOT/scripts/ec2-id.sh")"

aws ec2 reboot-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$IID" >/dev/null
echo "Reboot requested. Waiting 20s then showing status..."
sleep 20
"$ROOT/scripts/ec2-status.sh"
