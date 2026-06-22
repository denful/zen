#!/usr/bin/env bash
set -euo pipefail
RUNS=${RUNS:-10}
WARMUP=${WARMUP:-3}
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Zen vs nixpkgs — 10000 modules, listOf submodule stress ==="
echo ""
echo "--- Correctness (zen-nixpkgs compat must match nixpkgs exactly) ---"
RESULT=$(nix-instantiate --eval --strict "$DIR/verify.nix" 2>/dev/null)
if echo "$RESULT" | grep -q 'pass = true'; then
  echo "✅ zen.nixmod output matches lib.evalModules"
else
  echo "❌ MISMATCH:"
  echo "$RESULT"
  exit 1
fi
echo ""
echo "--- Benchmark 1: zen-compat (both load nixpkgs) ---"
hyperfine \
  --warmup "$WARMUP" --runs "$RUNS" --shell none \
  --command-name "nixpkgs/lib.evalModules" "nix-instantiate --eval --strict $DIR/stress-nixpkgs.nix" \
  --command-name "zen/nixmod.evalModules" "nix-instantiate --eval --strict $DIR/stress-zen.nix"
echo ""
echo "--- Benchmark 2: zen-native (no nixpkgs import) vs nixpkgs ---"
hyperfine \
  --warmup "$WARMUP" --runs "$RUNS" --shell none \
  --command-name "nixpkgs/lib.evalModules" "nix-instantiate --eval --strict $DIR/stress-nixpkgs.nix" \
  --command-name "zen-native (no nixpkgs)" "nix-instantiate --eval --strict $DIR/stress-zen-native.nix"
