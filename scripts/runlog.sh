#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/runlog.sh -- <command...>
#   ./scripts/runlog.sh --tag "mytag" --snapshot manifests/samples.txt -- <command...>

TAG=""
SNAPSHOTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --snapshot) SNAPSHOTS+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--tag TAG] [--snapshot PATH] -- <command...>" >&2
  exit 2
fi

TS="$(date +"%Y-%m-%d_%H-%M-%S")"
USER_NAME="$(id -un 2>/dev/null || echo unknown)"
HOST_NAME="$(hostname -s 2>/dev/null || hostname)"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
CWD="$(pwd)"

SAFE_TAG=""
if [[ -n "$TAG" ]]; then
  SAFE_TAG="_$(echo "$TAG" | tr -cd '[:alnum:]_.-')"
fi

RUN_DIR="$GIT_ROOT/logs/runs/${TS}${SAFE_TAG}"
mkdir -p "$RUN_DIR"

# Metadata
{
  echo "timestamp: $TS"
  echo "user: $USER_NAME"
  echo "host: $HOST_NAME"
  echo "cwd: $CWD"
  echo "git_root: $GIT_ROOT"
  echo "git_sha: $GIT_SHA"
  echo "command: $*"
} > "$RUN_DIR/meta.txt"

# Optional snapshots
if [[ ${#SNAPSHOTS[@]} -gt 0 ]]; then
  mkdir -p "$GIT_ROOT/logs/inputs/${TS}${SAFE_TAG}"
  for p in "${SNAPSHOTS[@]}"; do
    if [[ -e "$p" ]]; then
      cp -a "$p" "$GIT_ROOT/logs/inputs/${TS}${SAFE_TAG}/"
    else
      echo "snapshot missing: $p" >> "$RUN_DIR/meta.txt"
    fi
  done
fi

# Run + log outputs
# - stdout/stderr captured to files
# - also echoed to terminal
set +e
("$@") \
  > >(tee "$RUN_DIR/stdout.log") \
  2> >(tee "$RUN_DIR/stderr.log" >&2)
EC=$?
set -e

echo "$EC" > "$RUN_DIR/exit_code.txt"
exit "$EC"
