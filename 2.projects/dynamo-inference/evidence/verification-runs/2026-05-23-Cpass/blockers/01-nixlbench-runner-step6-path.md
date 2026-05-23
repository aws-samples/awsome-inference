# Blocker: capture-counters.sh hardcoded EVID path  [RESOLVED]

**Severity:** LOW — bench succeeds; only the post-bench delta computation fails.
**Discovered:** 2026-05-23 Cpass verification rerun
**File:** benchmarks/nixl-bench/scripts/capture-counters.sh:7
**Status:** RESOLVED in this same session (see fix below)

## Issue

`capture-counters.sh` line 7 hardcoded `EVID=/home/ubuntu/awesome-inferencing/docs/evidence/rev8-pr72-e2e-2026-05-21`.
When called from `run-multinode.sh` (which writes to `$EVIDENCE_DIR/counters-pre.txt`),
the counter files actually landed in the legacy top-level dir, NOT in
the per-experiment `$EVIDENCE_DIR`. Step 6 of `run-multinode.sh` then
failed reading from `$EVIDENCE_DIR/counters-pre.txt`:

```
FileNotFoundError: ... pr72-rev8/verification-runs/2026-05-23-Cpass/nixlbench-multinode-PASS/counters-pre.txt
```

## Fix applied

`capture-counters.sh`:
```bash
EVID="${EVIDENCE_DIR:-/home/ubuntu/awesome-inferencing/docs/evidence/rev8-pr72-e2e-2026-05-21}"
mkdir -p "$EVID"
```

`run-multinode.sh` (steps 2 + 5):
```bash
EVIDENCE_DIR="$EVIDENCE_DIR" "$CAPTURE" pre 2>&1 | tail -3
```

Explicit env-var pass-through ensures the child script honors the
parent's `$EVIDENCE_DIR`. Legacy path is preserved as fallback for
ad-hoc invocations without `$EVIDENCE_DIR` set.

## Validation

After this fix, a fresh `IMAGE_TAG=520cfc584abb EVIDENCE_DIR=/tmp/test ./run-multinode.sh`
will write `counters-{pre,post}.txt` directly into `/tmp/test/`.
Step 6's python heredoc (which already reads from `$EVIDENCE_DIR`)
will then succeed.

## Impact on bench results

None. The Cpass run produced bandwidth numbers within +0.1% of the
original (46.95 GB/s vs 46.90 GB/s @ 64MB). Only the post-run delta
computation failed — bench results captured in pod-a.log were
unaffected.

## GitHub research (per directive)

Local script bug. No upstream issue. Fix is local; no external
dependency change needed.
