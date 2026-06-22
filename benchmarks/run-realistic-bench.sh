#!/usr/bin/env bash
# Realistic NixOS-config-shaped benchmark: zen vs nixpkgs lib.evalModules
#
# Workload: M service modules, K instances/submodule per module.
# N = M * (4 scalars + K instances + 2 path entries) (approximate effective options).
# Tested at M in {17,50,133,300}, K=4 — matching the proven result table.
#
# Measures nrPrimOpCalls via NIX_SHOW_STATS (interaction count proxy).
# Verifies byte-identical output via jq -S (canonical JSON diff).
#
# Run the full table:   bash benchmarks/run-realistic-bench.sh
# Run single point:     MS=50 KS=4 bash benchmarks/run-realistic-bench.sh
# Custom DZM path:      DZM_PATH=/path/to/zen bash benchmarks/run-realistic-bench.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
MS=(${MS:-17 50 133 300})
KS=(${KS:-4})
WORKDIR="$(mktemp -d /tmp/zen-realistic-bench.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

extract_primops() {  # $1 = stats JSON path
  jq -r '.nrPrimOpCalls' "$1"
}

measure_one() {  # $1=ENGINE $2=M $3=K  -> writes stats + eq JSON, echoes primops or ERR
  local engine="$1" M="$2" K="$3"
  local nix_src="${WORKDIR}/run-${engine}-M${M}-K${K}.nix"
  local stats="${WORKDIR}/stats-${engine}-M${M}-K${K}.json"
  local out="${WORKDIR}/out-${engine}-M${M}-K${K}.json"
  local err="${WORKDIR}/err-${engine}-M${M}-K${K}.txt"

  bash "$DIR/gen-realistic.sh" "$engine" "$M" "$K" > "$nix_src"

  local rc=0
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$stats" \
    timeout 30 nix-instantiate --eval --strict --json "$nix_src" \
    > "$out" 2> "$err" || rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "ERR(rc=${rc})"
    tail -3 "$err" >&2
    return
  fi
  if [[ ! -f "$stats" ]]; then
    echo "ERR(no-stats)"
    return
  fi
  extract_primops "$stats"
}

# jq-canonical equality gate: returns 0 (equal) or 1 (diff)
eq_check() {  # $1=zen-out $2=nixpkgs-out  (both JSON files)
  local dout="$1" nout="$2"
  if [[ ! -f "$dout" || ! -f "$nout" ]]; then echo "SKIP(missing)"; return 1; fi
  local da na
  da=$(jq -S . "$dout" 2>/dev/null) || { echo "ERR(jq-zen)"; return 1; }
  na=$(jq -S . "$nout" 2>/dev/null) || { echo "ERR(jq-nixpkgs)"; return 1; }
  if [[ "$da" == "$na" ]]; then echo "EQUAL"; return 0; else echo "DIFF"; return 1; fi
}

echo "Realistic NixOS-config bench: zen vs nixpkgs lib.evalModules"
echo "Workload: M service modules × K submod instances + scalar opts + mkDefault/mkForce + mkMerge paths + sparse cross-refs"
echo "Metric: nrPrimOpCalls (NIX_SHOW_STATS) — lower is better."
echo ""
printf '%-6s %-4s | %-12s | %-12s | %-8s | %s\n' "M" "K" "zen" "nixpkgs" "ratio" "eq?"
printf -- '-------+------+--------------+--------------+----------+------\n'

declare -A DZM_PO NP_PO
for M in "${MS[@]}"; do
  for K in "${KS[@]}"; do
    zen_po=$(measure_one zen "$M" "$K")
    np_po=$(measure_one nixpkgs "$M" "$K")

    eq_out="${WORKDIR}/out-zen-M${M}-K${K}.json"
    np_out="${WORKDIR}/out-nixpkgs-M${M}-K${K}.json"
    eq=$(eq_check "$eq_out" "$np_out")

    ratio="n/a"
    if [[ "$zen_po" =~ ^[0-9]+$ && "$np_po" =~ ^[0-9]+$ && "$zen_po" -gt 0 ]]; then
      ratio=$(awk "BEGIN{printf \"%.1f×\", ${np_po}/${zen_po}}")
    fi

    printf '%-6s %-4s | %-12s | %-12s | %-8s | %s\n' "$M" "$K" "$zen_po" "$np_po" "$ratio" "$eq"
    DZM_PO["${M}_${K}"]="$zen_po"
    NP_PO["${M}_${K}"]="$np_po"
  done
done

echo ""
echo "All byte-equality checks above should show EQUAL (jq -S canonical diff)."
echo "zen wins when ratio >> 1 and zen primops < nixpkgs primops on every row."
