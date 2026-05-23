# KR 2.3 — TRT-LLM path decision on Dynamo 1.2.0

**Status:** DRAFT. Fires when KR 2.1 detects `nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.2.0` public, OR NVIDIA announces that 1.2.0 stable ships without TRT-LLM.

**Owner:** Anton Alexander
**Contributor:** Wenhan Tan (NVIDIA) — confirm the premise
**Target outcome:** one of three options below, documented before we bump the combined image to 1.2.0.

---

## Premise

`docs/OKRS-2026-05-06.md` KR 2.3 asserts:

> Dev.2 [of 1.2.0] exists as `nvstaging` but we cannot consume it. DS-V4 dev.2 drops TRT-LLM entirely; it's vLLM + SGLang only. Our combined image ships both backends.

Before the public 1.2.0 tag drops, we decide which of three paths we commit to for the combined image. The decision affects customers who pull `dynamo-efa:<1.2.0-SHA>` and call `-e DYNAMO_BACKEND=trtllm`.

## The three paths

### Path A — Keep TRT-LLM via `tensorrtllm-runtime:1.1.0`

Combined image `FROM`s `nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.1.0` even when the vLLM + frontend stages move to 1.2.0.

**Pros:**
- Minimal customer churn. `DYNAMO_BACKEND=trtllm` continues to work.
- Avoids a rewrite of the combined image's `trtllm-stage` layout.
- Keeps a working TRT-LLM DeepEP path (`TRTLLM_FORCE_ALLTOALL_METHOD=DeepEP`) available for MoE workloads.

**Cons:**
- Runtime version skew inside the same image (vLLM 1.2.0, TRT-LLM 1.1.0). CUDA stack may diverge.
- NVIDIA will not backport fixes to the 1.1.0 TRT-LLM runtime once 1.2.0 is the public line. Support cliff.
- Creates a long-term maintenance hazard (CVE surface grows on the pinned 1.1.0 layer).
- Implicit customer expectation that TRT-LLM keeps working indefinitely.

**Cost:** low today, high later. Every Dynamo version bump past 1.2.0 forces us to re-evaluate whether to keep trailing 1.1.0 TRT-LLM.

### Path B — Add SGLang as the third backend, keep TRT-LLM on 1.1.0

Extend the combined image to three stages: `vllm-stage` + `sglang-stage` + `trtllm-stage`, with `DYNAMO_BACKEND=vllm|sglang|trtllm` switching between them.

**Pros:**
- Aligns with NVIDIA's 1.2.0 direction (vLLM + SGLang as the primary pair).
- Customers get SGLang without a rebuild.
- Future-proofs the image if NVIDIA drops TRT-LLM permanently in 1.3.x.
- Matches the blog v6 narrative that claims engine-agnostic coverage of vLLM / SGLang / TRT-LLM.

**Cons:**
- Image size grows. Three runtimes = three PyTorch ABI chains, three sets of Python site-packages, three CUDA minor-version stacks.
- Build time grows. AWS CodeBuild run goes from ~45 min to likely ~70 min cold.
- Inherits Path A's TRT-LLM-on-1.1.0 support cliff.
- Requires SGLang-on-DeepEP work (SGLang has DeepEP support but our `sglang-deepep-working/` isn't wired into the combined image yet).

**Cost:** medium today (one-time SGLang integration work), medium later (image bloat, build time, CVE surface).

### Path C — Drop TRT-LLM, vLLM + SGLang only

Combined image becomes `dynamo-combined-vllm-sglang-efa`. `DYNAMO_BACKEND=trtllm` is deprecated. Customers who need TRT-LLM pull `nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.2.0` directly (if NVIDIA keeps publishing it) or use the stand-alone `trtllm-deepep-working/` image we maintain separately.

**Pros:**
- Matches NVIDIA's direction exactly. Lowest ongoing complexity.
- Image size drops (~30% smaller based on the trtllm-stage layer size).
- Build time drops (~25 min cold instead of ~45).
- Clean story for customers: "combined image = vLLM + SGLang; use our stand-alone images for TRT-LLM."

**Cons:**
- Breaking change for any customer using `DYNAMO_BACKEND=trtllm`. Requires a clear deprecation window (recommend: 1.1.0 image remains live for 6 months after 1.2.0 ships).
- Blog v6 claims about engine-agnostic coverage need an amendment.
- Stand-alone `trtllm-deepep-working/` image becomes the new canonical TRT-LLM path, which forces us to actually maintain it (currently tagged v1 on `deepep-base:v1` with no v2 refresh planned).

**Cost:** medium today (deprecation messaging + customer comm), low later (clean break, no skew).

## Decision criteria

The call depends on two questions we can't answer today:

1. **Does NVIDIA publish `tensorrtllm-runtime:1.2.0` or not?**
   - If yes with DeepEP parity → Path B or C is straightforward.
   - If yes but DeepEP support dropped → Path C is forced.
   - If no → Path A becomes the only way to keep TRT-LLM alive, trailing indefinitely.
2. **How many customers use `DYNAMO_BACKEND=trtllm` today?**
   - If >25% of combined-image pulls → Path C is a breaking change that needs a real deprecation plan.
   - If <5% → Path C is trivial; Path A is over-kill; Path B is over-invested.

Until we have both answers, **provisional pick is Path C** on the following rationale:

- We already maintain `examples/trtllm-deepep-working/` as the canonical TRT-LLM + DeepEP path. Cutting TRT-LLM from the combined image formalizes what's already the separation of concerns.
- Path A's "just keep 1.1.0" defers the pain but doesn't remove it. Every future Dynamo bump is a re-decision. That's not OKR-compatible.
- Path B's SGLang integration is work we should do *anyway* (it unblocks the blog v6 engine-agnostic claim), but bundling it with the TRT-LLM decision conflates two questions.

## Action items when 1.2.0 lands

In order:

1. Pull `tensorrtllm-runtime:1.2.0` (or confirm absence). Measure DeepEP support via the harness we use for v1.
2. Snapshot combined-image pull analytics from ECR Public to estimate TRT-LLM customer share.
3. Circulate this doc + the two data points to the co-author list (Wenhan + AWS editorial + Baladithya).
4. If Path C wins: announce deprecation in the blog v6 post-publication update, keep 1.1.0 combined image ECR-live for 6 months, document the `trtllm-deepep-working/` stand-alone as the canonical TRT-LLM replacement.
5. If Path B wins: open a parallel branch `feature/sglang-backend-in-combined` to add `sglang-stage`. Budget one H100 window for validation.
6. Document the decision in `docs/OKRS-2026-05-06.md` under KR 2.3 with the rationale.

## Dependencies

- **KR 2.1** (Dynamo 1.2.0 NGC poller) must detect the public tag first.
- **KR 2.2** (B200 access) is independent — DS-V4 workloads need B200 regardless of backend.
- **KR 3.1** (`deepep-base:v2`) is upstream of this decision — `trtllm-deepep-working:v2` needs to be a working image on v2 before Path C can call it "the canonical replacement."

## Non-goals

- No image rebuild today. This is a paper decision pending KR 2.1 trigger.
- No retire of the current 1.1.0 combined image. It stays live until the decision is executed.
