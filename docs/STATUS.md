# EmbarrassinglyFasta2 — Project Status

Last updated: 2026-02-18

## Goal
Build an optimized, reproducible FASTQ → VCF pipeline runtime/orchestration layer designed for GPU-enabled EC2 execution (with local development support), focusing on high throughput and low orchestration overhead.

## Repository
- GitHub: DJWalsh27/EmbarrassinglyFasta2
- Default branch: main
- Local layout:
  - `src/` core library code (in progress)
  - `scripts/` operational scripts (logging + EC2 lifecycle)
  - `manifests/` environment/config manifests (includes gitignored secrets)
  - `docs/` documentation
  - `logs/`, `results/` local-only outputs

## Current setup (working)
### AWS CLI quality-of-life
- AWS CLI pager is disabled so commands don’t drop into `less`.
- Optional helper function `cap` exists to limit output in the terminal.

### S3
- S3 bucket is reachable from the default AWS CLI profile.
- Bucket is configured with public access blocked and bucket-owner enforced object ownership.

### EC2 lifecycle scripts
The repository includes scripts to manage EC2 instances:
- `scripts/ec2-launch-4gpu.sh` (spot-first, 4-GPU intent, on-demand fallback)
- `scripts/ec2-status.sh`
- `scripts/ec2-start.sh`
- `scripts/ec2-stop.sh`
- `scripts/ec2-reboot.sh`
- `scripts/ec2-terminate.sh`
- State is stored locally in `manifests/ec2.state` (gitignored).

### Logging
- `scripts/runlog.sh` provides timestamped command logging into `logs/runs/<timestamp>_<tag>/`.

## What we validated today
### Instance provisioning
- Successfully launched an on-demand GPU instance after fixing:
  - AMI lookup (using EC2 DescribeImages, avoiding SSM parameter dependency).
  - KeyPair naming mismatch (using the existing EC2 KeyPair name, not the local file name).
- Stop and terminate scripts work correctly:
  - Stop transitions instance to `stopped`.
  - Terminate requires an explicit `--yes` and then clears local state.

### Connectivity note (important)
- Direct SSH (port 22) from this Mac/network was not reachable (TCP timeout), even when inbound rules allowed it.
- AWS Console/EC2 Connect access did work, indicating the instance was healthy but the local network likely blocks outbound TCP/22 (and even GitHub SSH port 22).

## Known issues / risks
1) Local networks appear to block outbound SSH on port 22.
   - Workarounds:
     - Use EC2 Instance Connect / AWS console tooling, or
     - Use SSH over 443 via a bastion or VPN (future), or
     - Use SSM Session Manager once an instance profile + IAM permissions are in place.

2) SSM agent was installed and running on the instance, but the instance had no IAM instance profile attached.
   - Result: SSM could not acquire credentials to register fully for Session Manager access.

## Next steps (prioritized)
1) Make remote access reliable:
   - Prefer SSM Session Manager (requires attaching an instance profile with SSM permissions).
   - If SSM is not possible, establish an alternative SSH path that works from typical networks (e.g., VPN/bastion/port-443 strategy).

2) Harden and simplify EC2 automation:
   - Ensure `ec2-launch-4gpu.sh`:
     - selects the cheapest available 4-GPU instance type in-region (spot-first, on-demand fallback),
     - uses a consistent security group strategy,
     - uses a consistent subnet/AZ selection strategy (and documents it),
     - always attaches 1TB gp3 root volume.

3) Add a permissions self-check script (non-destructive):
   - A single command to report PASS/FAIL for required EC2/IAM/SSM actions without launching resources.

