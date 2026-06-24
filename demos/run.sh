#!/usr/bin/env bash
# demos/run.sh — side-by-side investor showcase: nixpkgs vs dzm
# Each side runs in its own nix-instantiate invocation so a nixpkgs abort
# never kills the dzm side (or the next demo).
# Capture via `2>&1; echo exit=$?` pattern — a nixpkgs abort does not kill
# the script.
set -uo pipefail

DEMOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sep() { printf '\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
hdr() { printf '\n  %s\n' "$*"; }

# capture <nix-file> — runs nix-instantiate, sets $OUT and $RC
capture() {
  OUT=$(nix-instantiate --eval --strict "$1" 2>&1) && RC=0 || RC=$?
}

# ─────────────────────────────────────────────────────────────────────────────
sep
hdr "DEMO 1 — Accumulating blame (two wrong-typed options)"
hdr "nixpkgs: aborts on the FIRST type error, never surfaces the second."
hdr "dzm:     returns ALL errors in left.errors — both faults, zero aborts."
sep

printf '\n'
printf '  nixpkgs side:\n'
capture "$DEMOS_DIR/blame/nixpkgs-side.nix"
printf '  nixpkgs: ABORTS exit=%s\n' "$RC"
printf '%s\n' "$OUT" | grep -E "error:|not of type" | head -3 | sed 's/^/    /'

printf '\n'
printf '  dzm side:\n'
capture "$DEMOS_DIR/blame/dzm-side.nix"
printf '  dzm:     clean exit=%s\n' "$RC"
printf '  result:  %s\n' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
sep
hdr "DEMO 2 — Cycle detection (mutual option reference a<->b)"
hdr "nixpkgs: 'infinite recursion encountered' -- unlocated, uncatchable throw."
hdr "dzm:     Kahn topo-sort -> located {why=cycle; cycle=[...]} -- no throw."
sep

printf '\n'
printf '  nixpkgs side:\n'
capture "$DEMOS_DIR/cycle/nixpkgs-side.nix"
printf '  nixpkgs: ABORTS exit=%s\n' "$RC"
printf '%s\n' "$OUT" | grep -E "infinite recursion|error:" | head -3 | sed 's/^/    /'

printf '\n'
printf '  dzm side:\n'
capture "$DEMOS_DIR/cycle/dzm-side.nix"
printf '  dzm:     clean exit=%s\n' "$RC"
printf '  result:  %s\n' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
sep
hdr "DEMO 3 — Stateful running-total actor ([10,20,30] -> [10,30,60])"
hdr "nixpkgs: zero actor primitives in lib/modules.nix (become/inbox/scanl = 0)."
hdr "dzm:     typed zen.t.actor + zen.send -> per-step totals as a module option."
sep

printf '\n'
printf '  nixpkgs side (capability gap -- no typed actor/send primitive):\n'
capture "$DEMOS_DIR/actor/nixpkgs-side.nix"
printf '  nixpkgs: exit=%s\n' "$RC"
printf '  result:  %s\n' "$OUT"
printf '  note:    grep become/inbox/scanl in lib/modules.nix = 0 runtime primitives\n'
printf '           (1 match is a comment: "might become obsolete", not a function)\n'

printf '\n'
printf '  dzm side:\n'
capture "$DEMOS_DIR/actor/dzm-side.nix"
printf '  dzm:     clean exit=%s\n' "$RC"
printf '  result:  %s\n' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
sep
hdr "DEMO 4 — Value-dependent option EXISTENCE (actor 'become')"
hdr "enable's VALUE flips which options exist: true -> {turbo,maxSpeed} ARE the"
hdr "interface; false -> they are NOT (present -> located error)."
hdr "nixpkgs: config-dependent DECLARATION -> 'infinite recursion encountered'."
hdr "dzm:     fx Sigma + large elimination in the check seam -> shape flips, no abort."
sep

printf '\n'
printf '  nixpkgs side (declare turbo only when enable -> config-in-imports):\n'
capture "$DEMOS_DIR/behaviour/nixpkgs-side.nix"
printf '  nixpkgs: ABORTS exit=%s\n' "$RC"
printf '%s\n' "$OUT" | grep -E "error: infinite recursion|reference .config. in .imports." | head -2 | sed 's/^/    /'

printf '\n'
printf '  dzm side:\n'
capture "$DEMOS_DIR/behaviour/dzm-side.nix"
printf '  dzm:     clean exit=%s\n' "$RC"
printf '  result:  %s\n' "$OUT"
printf '  note:    enable flips the accepted option SHAPE; absent/present enforced\n'
printf '           per behaviour (NOT a literal lens-key change — that shares the\n'
printf '           nixpkgs lazy-fixpoint limit; this is the strongest runnable form).\n'

sep
printf '\n'
printf '  SUMMARY\n'
printf '  %-30s  %s\n' "scenario" "nixpkgs vs dzm"
printf '  %-30s  %s\n' "------------------------------" "------------------------------------------"
printf '  %-30s  %s\n' "blame (2 type errors)" "ABORTS on 1st  vs  ALL errors returned"
printf '  %-30s  %s\n' "cycle (a<->b)" "infinite recursion  vs  located {why=cycle}"
printf '  %-30s  %s\n' "actor ([10,20,30])" "final=60 only  vs  totals=[10,30,60]"
printf '  %-30s  %s\n' "option existence (enable)" "infinite recursion  vs  shape flips per value"
printf '\n'
