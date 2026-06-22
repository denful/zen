#!/usr/bin/env bash
# 3-way CHAIN count-bench: zen vs zen-old vs nixpkgs.
#
# Measures eval COUNTERS (nrPrimOpCalls, nrThunks) via NIX_SHOW_STATS — NOT
# wall-time — at N in {100,500,1000,2000}. Each engine evaluates the SAME linear
# chain (o_k = o_{k-1}+1). Counts are extracted verbatim from the NIX_SHOW_STATS
# JSON; nothing is massaged.
#
# zen uses literal-pattern source (gen-zen-chain.sh) because its edge-local
# engine reads deps via builtins.functionArgs (literal patterns only). zen-old +
# nixpkgs take N via --argstr.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
NS=(${NS:-100 500 1000 2000})
STATS=/tmp/zen-bench-stats.json
TMPDZM=/tmp/zen-chain-src
NIXOPTS=()

extract() { # $1 = key ; reads $STATS
  grep "\"$1\":" "$STATS" | head -1 | tr -dc '0-9'
}

# eval an expression/file, capture stats, echo "primops thunks" or "ERR"
measure() {
  rm -f "$STATS"
  if NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$STATS" \
     timeout 300 nix-instantiate "${NIXOPTS[@]}" --eval --strict "$@" >/dev/null 2>/tmp/zen-bench-err; then
    if [[ -f "$STATS" ]]; then
      echo "$(extract nrPrimOpCalls) $(extract nrThunks)"
    else
      echo "ERR(no-stats)"
    fi
  else
    echo "ERR(eval rc=$?)"
  fi
}

printf '%-8s | %-22s | %-22s | %-22s\n' "N" "zen (primops/thunks)" "zen-old (primops/thunks)" "nixpkgs (primops/thunks)"
printf -- '---------+------------------------+------------------------+------------------------\n'

declare -A DZM_PO ZEN_PO NIX_PO
for N in "${NS[@]}"; do
  bash "$DIR/gen-zen-chain.sh" "$N" > "$TMPDZM-$N.nix"
  d=$(measure "$TMPDZM-$N.nix")
  z=$(measure --argstr N "$N" "$DIR/chain-zen-old.nix")
  x=$(measure --argstr N "$N" "$DIR/chain-nixpkgs.nix")
  printf '%-8s | %-22s | %-22s | %-22s\n' "$N" "$d" "$z" "$x"
  DZM_PO[$N]=${d%% *}; ZEN_PO[$N]=${z%% *}; NIX_PO[$N]=${x%% *}
done

echo ""
echo "=== doubling ratios cost(2N)/cost(N) on nrPrimOpCalls (->2 linear, ->4 quadratic) ==="
printf '%-12s | %-10s | %-10s | %-10s\n' "pair" "zen" "zen-old" "nixpkgs"
ratio() { # $1 num $2 den
  if [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]]; then
    awk "BEGIN{printf \"%.2f\", $1/$2}"
  else echo "n/a"; fi
}
prev=""
for N in "${NS[@]}"; do
  if [[ -n "$prev" ]]; then
    printf '%-12s | %-10s | %-10s | %-10s\n' "${prev}->${N}" \
      "$(ratio "${DZM_PO[$N]}" "${DZM_PO[$prev]}")" \
      "$(ratio "${ZEN_PO[$N]}" "${ZEN_PO[$prev]}")" \
      "$(ratio "${NIX_PO[$N]}" "${NIX_PO[$prev]}")"
  fi
  prev=$N
done

echo ""
LAST=${NS[-1]}
echo "=== >=10x GATE at largest N=$LAST (nrPrimOpCalls) ==="
echo "zen=${DZM_PO[$LAST]}  zen-old=${ZEN_PO[$LAST]}  nixpkgs=${NIX_PO[$LAST]}"
if [[ "${DZM_PO[$LAST]}" =~ ^[0-9]+$ && "${ZEN_PO[$LAST]}" =~ ^[0-9]+$ && "${NIX_PO[$LAST]}" =~ ^[0-9]+$ ]]; then
  awk "BEGIN{
    zen=${DZM_PO[$LAST]}; zen=${ZEN_PO[$LAST]}; nix=${NIX_PO[$LAST]};
    mn=(zen<nix)?zen:nix;
    printf \"zen vs zen-old : %.2fx\\n\", zen/zen;
    printf \"zen vs nixpkgs : %.2fx\\n\", nix/zen;
    printf \"min(zen,nix)/zen = %.2fx  (gate needs >=10x)\\n\", mn/zen;
    printf (zen*10<=mn)?\"VERDICT: PERF-GATE-MET\\n\":\"VERDICT: PERF-GATE-MISSED\\n\";
  }"
fi
