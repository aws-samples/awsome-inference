# rev5 operator flow — from T12 outcome to PR #72 comment

Full sequence an operator follows once `t12-completions.log` is written.

## Pre-flight

```bash
cd docs/evidence/multinode-2026-05-06-rev5
# Ensure all 3 helper scripts are present
ls -la *.sh
# Expected: watch-t12.sh  fill-rev5-pass.sh  fill-rev5-nogo.sh
```

## Option A — passive watch

Run the watcher in a side terminal; it polls every 15 s and prints the
next-action when the log populates.

```bash
./watch-t12.sh
```

Exit 0 → PASS flow (below). Exit 2 → NO-GO flow (below).

## Option B — active run

Once T12 curl has been fired and `t12-completions.log` exists:

```bash
# Check which path you're on
python3 -c "
import json
try:
    d = json.load(open('t12-completions.log'))
    print('PASS' if d.get('choices',[{}])[0].get('text') else 'NO-GO')
except Exception:
    print('NO-GO' if open('t12-completions.log').read().strip() else 'PENDING')
"
```

## PASS flow

```bash
# 1. Populate the PR comment body
./fill-rev5-pass.sh 9467d1460c71

# 2. Review /tmp/rev5-pass-filled.md (fill any <FILL> placeholders the
#    script couldn't auto-populate — usually just T11 GB/s if the log
#    format drifted)

# 3. Fire
gh pr comment 72 --repo aws-samples/awsome-inference \
    --body-file /tmp/rev5-pass-filled.md

# 4. Update README.md in this dir: flip T12d row to PASS, commit
sed -i 's|T12d.*BLOCKED.*$|T12d Dynamo disagg /v1/completions | **PASS** |g' README.md
cd ../../..
git add docs/evidence/multinode-2026-05-06-rev5/
git commit -m "rev5 — T12d PASS on Dynamo 1.1.0"
git push origin feature/dynamo-combined-vllm-trtllm-efa
```

Total elapsed: **≈ 30 seconds** from T12 PASS → PR comment live.

## NO-GO flow

```bash
# 1. Populate both drafts
./fill-rev5-nogo.sh 9467d1460c71

# 2. Review /tmp/rev5-nogo-upstream-issue.md (check env matrix + logs
#    are accurate; fill any <tags> that didn't auto-populate)

# 3. File the upstream issue
gh issue create --repo ai-dynamo/dynamo \
    --title "KubeDiscoveryClient returns 0 instances in disagg vLLM on 1.0.1+1.1.0" \
    --body-file /tmp/rev5-nogo-upstream-issue.md

# 4. Note the returned issue number (e.g. 234), replace in PR comment
sed -i 's|<ISSUE-NUM>|234|g' /tmp/rev5-nogo-pr-comment.md

# 5. Fire PR #72 NO-GO comment
gh pr comment 72 --repo aws-samples/awsome-inference \
    --body-file /tmp/rev5-nogo-pr-comment.md

# 6. Update README.md in this dir: T12d → UPSTREAM-TRACKED
cd ../../..
git add docs/evidence/multinode-2026-05-06-rev5/
git commit -m "rev5 — T12d NO-GO on Dynamo 1.1.0, filed ai-dynamo/dynamo#234"
git push origin feature/dynamo-combined-vllm-trtllm-efa
```

Total elapsed: **≈ 2 minutes** from T12 NO-GO → both issue + PR comment live.

## Cleanup (either flow)

```bash
# Restore nvshmem replicas
kubectl scale -n nvshmem-efa statefulset deepep-nvshmem --replicas=2

# Release cluster lock
python3 -c "
import json, datetime
p = '$HOME/.claude/cluster-lock-h100.json'
d = json.load(open(p))
d['holder'] = None
d['claimed_at'] = None
d['purpose'] = None
d['released_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
d['queue'] = []
json.dump(d, open(p,'w'), indent=2)
"
```

## After either flow

- Update OKR doc `docs/OKRS-2026-05-06.md`:
  - KR 1.2: check off the T12 line, flip status 🟡 → 🟢 (PASS) or note blocked (NO-GO)
  - KR 1.3: check off the comment line
- If PASS: notify Alex for PR #72 review
- If NO-GO: PR #72 is still mergeable per the rev5 prelim close-out. The upstream issue becomes the next blocker to watch.
