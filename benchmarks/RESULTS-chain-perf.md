# PERF rung — zen CHAIN count-bench results (2026-06-22)

## HARNESS NOTE

Generator import path was stale (pointed at removed workspace `/home/vic/hk/workspace/zen-perf`); repointed to live repo `/home/vic/hk/zen`. Run: `nix-shell ./shell.nix --run 'bash benchmarks/run-chain-bench.sh'`.

## Workload

Linear chain `o_0 = 0`, `o_k = o_{k-1} + 1` (k=1..N). Measured by eval COUNTERS via `NIX_SHOW_STATS`, NOT wall-time. Head commit 1118e5d6.

Engines: zen (edge-local, per-key `{dep}:expr`) vs zen-old (whole-config-fn, `mapAttrs getVal srcs`) vs nixpkgs (`lib.evalModules`).

## nrPrimOpCalls / nrThunks (measured 2026-06-22)

| N    | zen (primops / thunks) | zen-old (primops / thunks) | nixpkgs (primops / thunks) |
|------|------------------------|----------------------------|----------------------------|
| 100  | 9663 / 55231           | 6316 / 47053               | 65569 / 196403             |
| 500  | 46463 / 262031         | 29916 / 221853             | 82769 / 246403             |
| 1000 | 92463 / 520531         | 59416 / 440353             | 104269 / 308903            |
| 2000 | 184463 / 1037531       | 118416 / 877353            | 147269 / 433903            |

## Doubling ratio cost(2N)/cost(N) on nrPrimOpCalls

| pair        | zen  | zen-old | nixpkgs |
|-------------|------|---------|---------|
| 100->500    | 4.81 | 4.74    | 1.26    |
| 500->1000   | 1.99 | 1.99    | 1.26    |
| 1000->2000  | 1.99 | 1.99    | 1.41    |

Asymptotic ratios: zen **1.99 LINEAR**, zen-old **1.99 LINEAR**, nixpkgs ~1.3.

## >=10x gate at N=2000

zen=184463, zen-old=118416, nixpkgs=147269.

- zen vs zen-old: **0.64x** (zen 56% MORE primops)
- zen vs nixpkgs: **0.80x** (zen 25% MORE primops)
- **PERF-GATE-MISSED**: needs >=10x, achieved ≤0.8x.

## VERDICT

**zen is O(N) LINEAR (1.99 doubling ratio)** — detectCycles O(N^2)→O(N) fix holds fresh at N up to 2000.

**zen slowest on chain**: 1.56x more primops than zen-old, 1.25x more than nixpkgs. Cause: same dnzl substrate as zen-old + zen desugar overhead.

**>=10x vs zen-old impossible in pure Nix** (same substrate); native dnet/Rust compile = only >=10x path. See `vic/notes/2026-06-22-perf-verdict.md`.
