#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"
IID="$("$ROOT/scripts/ec2-id.sh")"
STATE_FILE="${EC2_STATE_FILE:-$ROOT/manifests/ec2.state}"

# Safety: require --yes to terminate
if [[ "${1:-}" != "--yes" ]]; then
  echo "Refusing to terminate without --yes" >&2
  echo "Usage: scripts/ec2-terminate.sh --yes" >&2
  exit 2
fi

aws ec2 terminate-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$IID" >/dev/null
echo "Terminate requested for $IID"

# Clear state file (local)
rm -f "$STATE_FILE" || true
