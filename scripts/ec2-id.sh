#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh"
STATE_FILE="${EC2_STATE_FILE:-$ROOT/manifests/ec2.state}"

if [[ -n "${EC2_INSTANCE_ID:-}" ]]; then
  echo "$EC2_INSTANCE_ID"
  exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No instance id found. Create one with scripts/ec2-launch.sh" >&2
  exit 1
fi

cat "$STATE_FILE"
