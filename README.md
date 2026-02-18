# EmbarrassinglyFasta2

Runtime/orchestration layer for fast human WGS (FASTQ→VCF) using best-in-class tools with explicit GPU/CPU/NUMA placement.

## Layout
- src/        core python library
- scripts/    CLI entrypoints + helpers
- benchmarks/ benchmark harness + configs
- manifests/  sample lists + env configs
- docs/       runbooks + design docs
- updates/    dated progress notes
- logs/       runtime logs (ignored)
- results/    benchmark outputs (ignored)
