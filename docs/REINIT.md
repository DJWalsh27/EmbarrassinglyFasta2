# EmbarrassinglyFasta2 — Re-initiation / Handoff Document

Last updated: 2026-02-18  
Purpose: Single source of truth for goals, current status, access, and rehydration steps (useful when restarting with a new LLM/model or fresh machine/EC2).

---

## 1) Goal

Create an optimized FASTQ → VCF pipeline runtime/orchestration layer with:
- GPU-aware scheduling/placement (GPU pinning, CPU affinity/NUMA awareness)
- Reproducible runs and benchmarking
- Minimal overhead and high throughput for human 30× WGS
- No commercial licenses required (avoid Parabricks/DRAGEN; prefer open-source tools where possible)
- Cloud execution on EC2, local development supported

---

## 2) Current setup / status

### Repo
- Local path (Mac): `/Users/djw/Desktop/Codex/EmbarrassinglyFasta2`
- Branch: `main`
- GitHub remote: `git@github.com:DJWalsh27/EmbarrassinglyFasta2.git`
- GitHub SSH auth verified: `ssh -T git@github.com` ✅

### Directory layout
- `src/`        core library code (to be built)
- `scripts/`    helper scripts (includes `runlog.sh`)
- `benchmarks/` benchmark harness (to be built)
- `manifests/`  env/config manifests (contains `secrets.env` which is gitignored)
- `docs/`       documentation
- `updates/`    dated notes
- `logs/`       local logs only (not stored in git)
- `results/`    local outputs only (not stored in git)

### Logging
- Script: `scripts/runlog.sh`
- Output: creates `logs/runs/<timestamp>_<tag>/` containing:
  - `meta.txt`, `stdout.log`, `stderr.log`, `exit_code.txt`
- Example:
  - `./scripts/runlog.sh --tag sanity -- bash -lc "git status -sb && ls -la"`

### AWS CLI paging
- Paging disabled:
  - `export AWS_PAGER=""`
  - `aws configure set cli_pager ""`
- Optional: `cap` shell function exists to cap output lines manually.

---

## 3) Secrets / logins / access

### Principle
- Store operational defaults in `manifests/secrets.env` (gitignored).
- Never commit private keys, tokens, or sensitive data to git.
- Store only paths to keys and identifiers (account IDs, ARNs, bucket names), not raw secret material.

### Secrets file
- File: `manifests/secrets.env` (NOT committed)
- Template: `manifests/secrets.env.example` (committed)

Expected key values in `manifests/secrets.env`:
- AWS:
  - `AWS_PROFILE=default`
  - `AWS_REGION=us-east-1`
  - `AWS_ACCOUNT_ID=571600865484`
- S3:
  - `S3_BUCKET_RESULTS=gpu-fasta`
  - `S3_BUCKET_LOGS=gpu-fasta`
  - `S3_PREFIX=embfasta2/`
- EC2 defaults:
  - `EC2_DEFAULT_USER=ubuntu`
  - `EC2_SSH_KEY_PATH=~/.ssh/my-ec2-key`
  - `EC2_WORKDIR=/home/ubuntu/EmbarrassinglyFasta2`
  - `EC2_INSTANCE_ID=` (blank until instance created)
  - `EC2_INSTANCE_TAG_NAME=embfasta2-gpu`

### AWS profiles present on the Mac
- `default` (programmatic credentials) — confirmed S3 access to `gpu-fasta`
- `Ecotone_PowerUserAcces_Darren-571600865484` (SSO) — requires periodic login:
  - `aws sso login --profile Ecotone_PowerUserAcces_Darren-571600865484`

### S3 bucket
- Bucket: `gpu-fasta`
- Region: `us-east-1` (LocationConstraint null)
- Public access: blocked
- Object ownership: bucket owner enforced

---

## 4) Git details + download/update commands

### Clone fresh
```bash
git clone git@github.com:DJWalsh27/EmbarrassinglyFasta2.git
cd EmbarrassinglyFasta2
