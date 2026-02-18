#!/usr/bin/env bash
set -euo pipefail

# Loads manifests/secrets.env into the environment.
# Usage: source scripts/env.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="$ROOT/manifests/secrets.env"

if [[ ! -f "$SECRETS" ]]; then
  echo "Missing $SECRETS. Create it from manifests/secrets.env.example" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$SECRETS"

: "${AWS_REGION:?Set AWS_REGION in manifests/secrets.env}"
: "${AWS_PROFILE:=default}"

export AWS_REGION AWS_PROFILE
export AWS_PAGER="${AWS_PAGER:-}"
