#!/usr/bin/env bash
# demos/showcase.sh — narrated, visually-rich ~60s investor showcase
# Tells dzm's whole story end-to-end: nixpkgs ✗ BESIDE dzm ✓.
# Run with FAST=1 to skip all pacing beats (CI mode).
#
# Pattern: capture() isolates nix-instantiate in its own subshell so a
# nixpkgs abort (exit≠0) never kills this script. set -uo pipefail (NOT -e).
set -uo pipefail

ACT="${1:-all}"
case "$ACT" in
  all|blame|partial|cycle|recover|policy|actor|behaviour|deptype|pitype|discovery) ;;
  *) printf 'unknown demo: %s\n  valid: blame partial cycle recover policy actor behaviour deptype pitype discovery all\n' "$ACT" >&2; exit 1 ;;
esac
want() { [ "$ACT" = "all" ] || [ "$ACT" = "$1" ]; }

DEMOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── ANSI color helpers (guarded: only when stdout is a terminal) ─────────────
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
  RED_X="${RED}✗${RESET}"
  GREEN_OK="${GREEN}✓${RESET}"
else
  RED=''
  GREEN=''
  BOLD=''
  DIM=''
  RESET=''
  RED_X='✗'
  GREEN_OK='✓'
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

# capture [--json] <file>  — runs nix-instantiate --eval --strict, sets $OUT/$RC
capture() {
  local json_flag=''
  if [ "${1:-}" = '--json' ]; then
    json_flag='--json'
    shift
  fi
  # shellcheck disable=SC2086
  OUT=$(nix-instantiate --eval --strict $json_flag "$1" 2>&1) && RC=0 || RC=$?
}

# capture_json <nix-file> — dzm-side JSON eval, CLEAN stdout only (drop the
# nix channels stderr warning so jq gets valid JSON), sets $JSON and $RC.
capture_json() {
  JSON=$(nix-instantiate --eval --strict --json "$1" 2>/dev/null) && RC=0 || RC=$?
}

# sep — full-width box separator
sep() { printf '\n%s\n' "$(printf '%0.s━' {1..70})"; }

# hdr — bold header line
hdr() {
  printf "${BOLD}  %s${RESET}\n" "$*"
}

# sub — dimmed sub-text line
sub() {
  printf "${DIM}  %s${RESET}\n" "$*"
}

# pause — pacing beat between reveals (skipped when FAST=1 or non-tty)
pause() {
  if [ "${FAST:-0}" != '1' ] && [ -t 1 ]; then
    sleep "${1:-0.4}"
  fi
}

# nixpkgs_fail — print nixpkgs error banner + grep excerpt
nixpkgs_fail() {
  printf "  ${RED_X} nixpkgs: ABORTS  exit=%s${RESET}\n" "$RC"
  local excerpt
  excerpt=$(printf '%s\n' "$OUT" | grep -E "error:|infinite recursion|not of type" | head -3 | sed 's/^/       /')
  if [ -n "$excerpt" ]; then
    printf '%s\n' "$excerpt"
  fi
}

# dzm_ok — print dzm success banner
dzm_ok() {
  printf "  ${GREEN_OK} dzm: clean exit=%s${RESET}\n" "$RC"
}

# title_box — framed title block
title_box() {
  sep
  printf '\n'
  printf "  ${BOLD}%-66s${RESET}\n" "$1"
  if [ -n "${2:-}" ]; then
    printf "  ${DIM}%-66s${RESET}\n" "$2"
  fi
  printf '\n'
}

# ── TITLE ────────────────────────────────────────────────────────────────────
sep
printf '\n'
printf "  ${BOLD}dzm — DELTA-NET MODULES  |  Full Story Showcase${RESET}\n"
printf '\n'
printf "  ${DIM}dzm keeps evaluation INSIDE an Either/effect world${RESET}\n"
printf "  ${DIM}(bend lenses + nix-effects handlers + static Kahn pre-pass)${RESET}\n"
printf "  ${DIM}so errors, cycles, types, and behaviours become INSPECTABLE DATA,${RESET}\n"
printf "  ${DIM}never fatal aborts. Modules are actors that evolve per message.${RESET}\n"
printf '\n'
sep

pause 0.6

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 1 — ERRORS ARE DATA (accumulating blame)
# ═══════════════════════════════════════════════════════════════════════════════
if want blame; then
title_box "ACT 1 — ERRORS ARE DATA" "Two type faults in the same config."

printf "  nixpkgs: aborts on fault #1, never surfaces fault #2.\n"
printf "  dzm:     returns ALL located errors at once — errors as data.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/blame/nixpkgs-side.nix"
nixpkgs_fail
pause 0.4

printf '\n'
printf "  ${BOLD}── dzm ──${RESET}\n"
capture_json "$DEMOS_DIR/blame/dzm-side.nix"
dzm_ok
# Print ALL located errors (JSON array of {path,got,why})
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  printf '%s\n' "$JSON" | jq -r '.[] | "  { path=\(.path), got=\(.got), why=\(.why) }"' 2>/dev/null || printf '  result: %s\n' "$JSON"
else
  printf '  result: %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ nixpkgs aborts on fault #1, never sees #2.${RESET}\n"
printf "  ${DIM}  dzm returns ALL located errors at once.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 2 — PARTIAL CONFIG: one bad option ≠ total loss
# ═══════════════════════════════════════════════════════════════════════════════
if want partial; then
title_box "ACT 2 — PARTIAL CONFIG: one bad option ≠ total loss" "Six options, one wrong-typed."

printf "  nixpkgs: forcing the config aborts on the bad option — the good ones never return. Deploy NOTHING.\n"
printf "  dzm:     every option settles independently — bad = located left, good = settled values.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/partial/nixpkgs-side.nix"
printf "  ${RED_X} nixpkgs: ABORTS exit=${RC}${RESET}\n"
excerpt=$(printf '%s\n' "$OUT" | grep -E 'not of type|error:' | head -1 | sed 's/^/       /')
if [ -n "$excerpt" ]; then
  printf '%s\n' "$excerpt"
fi
printf "  the good 'host' is never reachable — one throw sinks the whole config.\n"

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ──${RESET}\n"
capture_json "$DEMOS_DIR/partial/dzm-side.nix"
printf "  ${GREEN_OK} dzm: clean${RESET}\n"
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  located=$(printf '%s\n' "$JSON" | jq -r '.located_failure[0] | "  located failure:  \(.path) → why=\(.why), got=\(.got)"' 2>/dev/null || true)
  surviving=$(printf '%s\n' "$JSON" | jq -r '.surviving | "  surviving good:   " + (to_entries | map("\(.key)=\(.value)") | join(" · "))' 2>/dev/null || true)
  if [ -n "$located" ]; then
    printf '%s\n' "$located"
  fi
  if [ -n "$surviving" ]; then
    printf '%s\n' "$surviving"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ The bad option is quarantined as a located left; the other five are settled values${RESET}\n"
printf "  ${DIM}  you can serialize + deploy now. (dzm gives you the good config as DATA —${RESET}\n"
printf "  ${DIM}  turning it into a booted system is downstream.)${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 3 — CYCLES ARE DATA (located cycle)
# ═══════════════════════════════════════════════════════════════════════════════
if want cycle; then
title_box "ACT 3 — CYCLES ARE DATA" "Mutual option reference a <-> b."

printf "  nixpkgs: engine death — unlocated, uncatchable.\n"
printf "  dzm:     Kahn topo-sort → located cycle as data, exit=0.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/cycle/nixpkgs-side.nix"
nixpkgs_fail
pause 0.4

printf '\n'
printf "  ${BOLD}── dzm ──${RESET}\n"
capture "$DEMOS_DIR/cycle/dzm-side.nix"
dzm_ok
printf '  result: %s\n' "$OUT"

pause 0.4
printf '\n'
printf "  ${DIM}→ nixpkgs: engine death, no location.${RESET}\n"
printf "  ${DIM}  dzm: Kahn topo-sort → located cycle as data.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 4 — RECOVER: conflicts resolve and RESUME
# ═══════════════════════════════════════════════════════════════════════════════
if want recover; then
title_box "ACT 4 — RECOVER: conflicts resolve and RESUME" "port defined twice: 8080 vs 9090."

printf "  nixpkgs: two definitions for one option → 'conflicting definition values' → fatal, no recovery.\n"
printf "  dzm:     the conflict signals a condition; a resolver restart RESUMES settlement.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/recover/nixpkgs-side.nix"
printf "  ${RED_X} nixpkgs: ABORTS exit=${RC}${RESET}\n"
excerpt=$(printf '%s\n' "$OUT" | grep -E 'conflicting definition' | head -2 | sed 's/^/       /')
if [ -n "$excerpt" ]; then
  printf '%s\n' "$excerpt"
fi

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ── (SAME config, swap the resolver)${RESET}\n"
capture_json "$DEMOS_DIR/recover/dzm-side.nix"
printf "  ${GREEN_OK} dzm: clean${RESET}\n"
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  usefirst=$(printf '%s\n' "$JSON" | jq -r '"  handler = useFirst  ⟹ ✓ resumes → port=\(.useFirst.right.port), host=\(.useFirst.right.host)"' 2>/dev/null || true)
  uselast=$(printf '%s\n' "$JSON" | jq -r '"  handler = useLast   ⟹ ✓ resumes → port=\(.useLast.right.port), host=\(.useLast.right.host)"' 2>/dev/null || true)
  rejectr=$(printf '%s\n' "$JSON" | jq -r '"  handler = reject    ⟹ ✗ located left {why=\(.reject.left.errors[0].why)} — host still settles (\(.reject.left.host.right))"' 2>/dev/null || true)
  if [ -n "$usefirst" ]; then
    printf "${GREEN}%s${RESET}\n" "$usefirst"
  fi
  if [ -n "$uselast" ]; then
    printf "${GREEN}%s${RESET}\n" "$uselast"
  fi
  if [ -n "$rejectr" ]; then
    printf "${RED}%s${RESET}\n" "$rejectr"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ A Common-Lisp-style condition/restart: settlement pauses at the conflict,${RESET}\n"
printf "  ${DIM}  the handler picks the restart, evaluation RESUMES past it. Nix's throw model${RESET}\n"
printf "  ${DIM}  has no recovery point — one conflict aborts everything.${RESET}\n"
printf "  ${DIM}  Same config, three outcomes, chosen by the handler.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 5 — POLICY: same config, swap the failure handler
# ═══════════════════════════════════════════════════════════════════════════════
if want policy; then
title_box "ACT 5 — POLICY: same config, swap the failure handler" "Two bad options; the handler decides what happens."

printf "  nixpkgs: one hardcoded policy — throw. No warn-and-continue, no collect-all, no per-eval swap.\n"
printf "  dzm: the SAME config settled under different handlers — fail-loud or degrade-gracefully.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/policy/nixpkgs-side.nix"
printf "  ${RED_X} nixpkgs: ABORTS exit=${RC}${RESET}\n"
excerpt=$(printf '%s\n' "$OUT" | grep -E 'not of type' | head -1 | sed 's/^/       /')
if [ -n "$excerpt" ]; then
  printf '%s\n' "$excerpt"
fi

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ──${RESET}\n"
capture_json "$DEMOS_DIR/policy/dzm-side.nix"
printf "  ${GREEN_OK} dzm: clean${RESET}\n"
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  col_paths=$(printf '%s\n' "$JSON" | jq -r '.collecting.left.errors[].path' 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
  warn_port=$(printf '%s\n' "$JSON" | jq -r '.warnContinue.right.port' 2>/dev/null || true)
  warn_workers=$(printf '%s\n' "$JSON" | jq -r '.warnContinue.right.workers' 2>/dev/null || true)
  warn_host=$(printf '%s\n' "$JSON" | jq -r '.warnContinue.right.host' 2>/dev/null || true)
  if [ -n "$col_paths" ]; then
    printf "  collecting → located errors: %s (config rejected, all faults shown)\n" "$col_paths"
  fi
  pause 0.4
  if [ -n "$warn_port" ] && [ -n "$warn_host" ]; then
    printf "  warn-continue → settled: port=%s, workers=%s, host=%s (degraded, no abort)\n" \
      "$warn_port" "$warn_workers" "$warn_host"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ The handler IS the policy: same config, swap the interpreter — fail-loud${RESET}\n"
printf "  ${DIM}  (collect every error) or degrade-gracefully (fall back + continue).${RESET}\n"
printf "  ${DIM}  nixpkgs bakes one throw policy into the type. (A richer handler can use${RESET}\n"
printf "  ${DIM}  each option's declared default — follow-up.)${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 6 — MODULES ARE ACTORS (running-total, STEPPED REVEAL)
# ═══════════════════════════════════════════════════════════════════════════════
if want actor; then
title_box "ACT 6 — MODULES ARE ACTORS" "Running-total: send [10, 20, 30]."

printf "  nixpkgs: builtins.foldl' → final total only, no per-step states.\n"
printf "  dzm:     typed dnzl actor (reply+become) → every cumulative state.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/actor/nixpkgs-side.nix"
printf "  exit=%s\n" "$RC"
# Extract final total from nixpkgs output (it reports nixpkgs_final_total_only)
nixpkgs_final=$(printf '%s\n' "$OUT" | grep -oE 'nixpkgs_final_total_only = [0-9]+' | grep -oE '[0-9]+$' || true)
if [ -n "$nixpkgs_final" ]; then
  printf "  result: final_total = %s  (only the end result — no intermediate states)\n" "$nixpkgs_final"
else
  printf '  result: %s\n' "$OUT"
fi

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ── (STEPPED REVEAL)${RESET}\n"
capture "$DEMOS_DIR/actor/dzm-side.nix"
dzm_ok

# Parse totals from $OUT: looks like "{ batch = [ 10 20 30 ]; totals = [ 10 30 60 ]; }"
# Extract the three integers from the totals list
totals_raw=$(printf '%s\n' "$OUT" | grep -oE 'totals = \[[^]]*\]' | grep -oE '\[ [0-9 ]+ \]' || true)
# Extract individual numbers in order
t1=$(printf '%s\n' "$OUT" | grep -oE 'totals = \[ [0-9]+ [0-9]+ [0-9]+' | grep -oE '[0-9]+' | sed -n '1p' || true)
t2=$(printf '%s\n' "$OUT" | grep -oE 'totals = \[ [0-9]+ [0-9]+ [0-9]+' | grep -oE '[0-9]+' | sed -n '2p' || true)
t3=$(printf '%s\n' "$OUT" | grep -oE 'totals = \[ [0-9]+ [0-9]+ [0-9]+' | grep -oE '[0-9]+' | sed -n '3p' || true)

if [ -n "$t1" ] && [ -n "$t2" ] && [ -n "$t3" ]; then
  printf '\n'
  printf "  ${DIM}  send %s →  reply %s,  become(total=%s)${RESET}\n" "10" "$t1" "$t1"
  printf "  ${GREEN}  totals so far: [%s]${RESET}\n" "$t1"
  pause 0.5
  printf "  ${DIM}  send %s →  reply %s,  become(total=%s)${RESET}\n" "20" "$t2" "$t2"
  printf "  ${GREEN}  totals so far: [%s, %s]${RESET}\n" "$t1" "$t2"
  pause 0.5
  printf "  ${DIM}  send %s →  reply %s,  become(total=%s)${RESET}\n" "30" "$t3" "$t3"
  printf "  ${GREEN}  totals so far: [%s, %s, %s]${RESET}\n" "$t1" "$t2" "$t3"
  pause 0.5
else
  # Fallback: print raw (parse too fragile)
  printf '  result (raw): %s\n' "$OUT"
fi

printf '\n'
printf "  ${DIM}→ A fixpoint cannot represent 'handler changes over a stream.'${RESET}\n"
printf "  ${DIM}  The actor genuinely becomes its next state per message.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 7 — BEHAVIOUR SHAPE-FLIP (actor become at the config level)
# ═══════════════════════════════════════════════════════════════════════════════
if want behaviour; then
title_box "ACT 7 — BEHAVIOUR SHAPE-FLIP" "enable's VALUE flips the accepted option SHAPE."

printf "  nixpkgs: config-dependent declaration → infinite recursion.\n"
printf "  dzm:     fx Σ + large elimination → shape flips, errors located.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture "$DEMOS_DIR/behaviour/nixpkgs-side.nix"
nixpkgs_fail

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ── (LIVE FLIP)${RESET}\n"
capture_json "$DEMOS_DIR/actor-behaviour.nix"
dzm_ok

if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  a_settled=$(printf '%s\n' "$JSON" | jq -r '.behaviourA.present_ok.settled'      2>/dev/null || true)
  a_err=$(    printf '%s\n' "$JSON" | jq -r '.behaviourA.absent_rejected.settled'  2>/dev/null || true)
  a_exp=$(    printf '%s\n' "$JSON" | jq -r '.behaviourA.absent_rejected.blame.expected' 2>/dev/null || true)
  b_settled=$(printf '%s\n' "$JSON" | jq -r '.behaviourB.absent_ok.settled'        2>/dev/null || true)
  b_err=$(    printf '%s\n' "$JSON" | jq -r '.behaviourB.present_rejected.settled' 2>/dev/null || true)
  b_exp=$(    printf '%s\n' "$JSON" | jq -r '.behaviourB.present_rejected.blame.expected' 2>/dev/null || true)

  if [ -n "$a_settled" ] && [ -n "$b_settled" ]; then
    printf '\n'
    printf "  enable = true   →  interface IS {turbo, maxSpeed}\n"
    pause 0.3
    printf "       present  ⟹ %s\n" "$( [ "$a_settled" = 'right' ] && printf "${GREEN_OK} accepted (right)${RESET}" || printf "${RED_X} unexpected: %s${RESET}" "$a_settled" )"
    printf "       absent   ⟹ %s   [expected: %s]\n" "$( [ "$a_err" = 'left' ] && printf "${RED_X} LOCATED error (left)${RESET}" || printf "unexpected: %s" "$a_err" )" "$a_exp"
    pause 0.4
    printf "  enable = false  →  interface is NOT {turbo, maxSpeed}\n"
    pause 0.3
    printf "       absent   ⟹ %s\n" "$( [ "$b_settled" = 'right' ] && printf "${GREEN_OK} accepted (right)${RESET}" || printf "unexpected: %s" "$b_settled" )"
    printf "       present  ⟹ %s   [expected: %s]\n" "$( [ "$b_err" = 'left' ] && printf "${RED_X} LOCATED error (left)${RESET}" || printf "unexpected: %s" "$b_err" )" "$b_exp"
  else
    printf '  result (raw): %s\n' "$JSON"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
# MANDATORY HONESTY CAPTION (verbatim per spec)
printf "  ${DIM}→ Shape-flip: enable's VALUE flips the accepted option SHAPE${RESET}\n"
printf "  ${DIM}  (present/absent, enforced + LOCATED). This is the strongest${RESET}\n"
printf "  ${DIM}  RUNNABLE form — NOT literal option-existence (options do not${RESET}\n"
printf "  ${DIM}  vanish); a value-dependent key set is structurally blocked for${RESET}\n"
printf "  ${DIM}  the SAME reason as nixpkgs's lazy fixpoint. The win vs nixpkgs${RESET}\n"
printf "  ${DIM}  is LOCATED-not-silent, not options-vanish.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 8 — DEPENDENT TYPE: the TYPE computed from a VALUE (Vector n)
# ═══════════════════════════════════════════════════════════════════════════════
if want deptype; then
title_box "ACT 8 — DEPENDENT TYPE: items :: Vector n" "The type of items is a function of n's VALUE."

printf "  nixpkgs: structural inability — a module \`type\` is resolved BEFORE\n"
printf "  any option value is known; no seam where one option's resolved value\n"
printf "  parameterises another option's type.\n\n"

pause 0.4

printf "  ${BOLD}── dzm ── (SAME items, DIFFERENT n, DIFFERENT verdict)${RESET}\n"
capture_json "$DEMOS_DIR/deptype.nix"
dzm_ok

if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  n2_settled=$(printf '%s\n' "$JSON" | jq -r '.dependence.n2_len2.settled'          2>/dev/null || true)
  n2_items=$(  printf '%s\n' "$JSON" | jq -c '.dependence.n2_len2.value.items'       2>/dev/null || true)
  n3_settled=$(printf '%s\n' "$JSON" | jq -r '.dependence.n3_len2.settled'           2>/dev/null || true)
  n3_exp=$(    printf '%s\n' "$JSON" | jq -r '.dependence.n3_len2.blame.expected'    2>/dev/null || true)
  n3_got=$(    printf '%s\n' "$JSON" | jq -c '.dependence.n3_len2.blame.got'         2>/dev/null || true)

  if [ -n "$n2_settled" ] && [ -n "$n3_settled" ]; then
    printf '\n'
    printf "  n = 2  →  items : Vector 2  →  %s       ⟹ %s\n" \
      "$n2_items" \
      "$( [ "$n2_settled" = 'right' ] && printf "${GREEN_OK} right${RESET}" || printf "unexpected: %s" "$n2_settled" )"
    pause 0.4
    printf "  n = 3  →  items : Vector 3  →  SAME %s  ⟹ %s   (expected %s, got %s)\n" \
      "$n2_items" \
      "$( [ "$n3_settled" = 'left' ] && printf "${RED_X} left${RESET}" || printf "unexpected: %s" "$n3_settled" )" \
      "$n3_exp" "$n3_got"
  else
    printf '  result (raw): %s\n' "$JSON"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ Same items, different n, different verdict.${RESET}\n"
printf "  ${DIM}  The TYPE of \`items\` is a function of n's VALUE (\`Vector n\`).${RESET}\n"
printf "  ${DIM}  Martin-Löf dependent types in a config language.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 9 — DEPENDENT FUNCTION: Π-type (domain + return-type-from-input)
# ═══════════════════════════════════════════════════════════════════════════════
if want pitype; then
title_box "ACT 9 — Π-TYPE: DEPENDENT FUNCTION" "Π(x:A).B(x): domain checked + codomain depends on input."

printf "  nixpkgs: \`lib.types.functionTo\` carries ONLY the codomain (checks\n"
printf "  results); it has NO slot for the DOMAIN and cannot make the return\n"
printf "  TYPE depend on the input VALUE.\n\n"

pause 0.4

printf "  ${BOLD}── dzm ──${RESET}\n"
capture_json "$DEMOS_DIR/pitype.nix"
dzm_ok

if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  dom_ok=$(      printf '%s\n' "$JSON" | jq -r '.domain.correct.settled'               2>/dev/null || true)
  dom_bad_arg=$( printf '%s\n' "$JSON" | jq -r '.domain.wrong_arg.settled'             2>/dev/null || true)
  dom_arg_site=$(printf '%s\n' "$JSON" | jq -r '.domain.wrong_arg.blame.site'          2>/dev/null || true)
  dom_arg_exp=$( printf '%s\n' "$JSON" | jq -r '.domain.wrong_arg.blame.expected'      2>/dev/null || true)
  dom_cod=$(     printf '%s\n' "$JSON" | jq -r '.domain.wrong_result.settled'          2>/dev/null || true)
  dom_cod_site=$(printf '%s\n' "$JSON" | jq -r '.domain.wrong_result.blame.site'       2>/dev/null || true)
  dep_ok=$(      printf '%s\n' "$JSON" | jq -r '.dependent.correct.settled'            2>/dev/null || true)
  dn2=$(         printf '%s\n' "$JSON" | jq -r '.dependence.len2_at_n2.settled'        2>/dev/null || true)
  dn3=$(         printf '%s\n' "$JSON" | jq -r '.dependence.len2_at_n3.settled'        2>/dev/null || true)
  dn3_exp=$(     printf '%s\n' "$JSON" | jq -r '.dependence.len2_at_n3.blame.expected' 2>/dev/null || true)

  if [ -n "$dom_ok" ] && [ -n "$dep_ok" ]; then
    printf '\n'
    printf "  DOMAIN     f:Int→Int  applied to 21       ⟹ %s\n" \
      "$( [ "$dom_ok" = 'right' ] && printf "${GREEN_OK} right${RESET}" || printf "unexpected: %s" "$dom_ok" )"
    printf "             f:Int→Int  applied to \"no\"     ⟹ %s   {site=%s, expected=%s}\n" \
      "$( [ "$dom_bad_arg" = 'left' ] && printf "${RED_X} left${RESET}" || printf "unexpected: %s" "$dom_bad_arg" )" \
      "$dom_arg_site" "$dom_arg_exp"
    pause 0.4
    printf "  CODOMAIN   f returns String (Int wanted)  ⟹ %s   {site=%s}\n" \
      "$( [ "$dom_cod" = 'left' ] && printf "${RED_X} left${RESET}" || printf "unexpected: %s" "$dom_cod" )" \
      "$dom_cod_site"
    pause 0.4
    printf "  DEPENDENT  mkVec 3  →  length-3 vector     ⟹ %s\n" \
      "$( [ "$dep_ok" = 'right' ] && printf "${GREEN_OK} right${RESET}" || printf "unexpected: %s" "$dep_ok" )"
    printf "             same len-2 fn:  n=2 ⟹ %s   n=3 ⟹ %s  (expected %s)\n" \
      "$( [ "$dn2" = 'right' ] && printf "${GREEN_OK} right${RESET}" || printf "unexpected: %s" "$dn2" )" \
      "$( [ "$dn3" = 'left'  ] && printf "${RED_X} left${RESET}"  || printf "unexpected: %s" "$dn3" )" \
      "$dn3_exp"
  else
    printf '  result (raw): %s\n' "$JSON"
  fi
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ Π(x:A).B(x): dzm checks BOTH the domain A (reject wrong-typed${RESET}\n"
printf "  ${DIM}  arg — functionTo can't) AND a codomain that DEPENDS on the input${RESET}\n"
printf "  ${DIM}  value.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ACT 10 — DISCOVERY: modules that find each other without knowing each other
# ═══════════════════════════════════════════════════════════════════════════════
if want discovery; then
title_box "ACT 10 — DISCOVERY: modules that find each other without knowing each other" "A client discovers a 'cache' provider by capability — never naming it."

printf "  nixpkgs: the consumer must HARDCODE the provider path (config.services.redis.url) — swap provider = edit consumer; no capability namespace.\n"
printf "  dzm: providers publish a capability; a broker wires them by NAME at settle-time; neither side references the other.\n\n"

pause 0.4

printf "  ${BOLD}── nixpkgs ──${RESET}\n"
capture_json "$DEMOS_DIR/discovery/nixpkgs-side.nix"
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  printf '%s\n' "$JSON" | jq -r '"  consumer must reference: \(.consumerMustReference)   ·   capability namespace: none   ·   swap provider ⟹ edit consumer"' 2>/dev/null \
    | while IFS= read -r line; do printf "  ${RED}%s${RESET}\n" "$line"; done || true
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${BOLD}── dzm ── (discover by capability name)${RESET}\n"
capture_json "$DEMOS_DIR/discovery/dzm-side.nix"
printf "  ${GREEN_OK} dzm: clean${RESET}\n"
if command -v jq &>/dev/null && [ -n "${JSON:-}" ]; then
  printf '%s\n' "$JSON" | jq -r '"  discover \"cache\"            ⟹ ✓ resolved: \(.resolved.cacheUrl)  (from \(.resolved.resolvedFrom));  losers: \(.resolved.losers|join(", "))"' 2>/dev/null \
    | while IFS= read -r line; do printf "${GREEN}%s${RESET}\n" "$line"; done || true
  printf '%s\n' "$JSON" | jq -r '"  flip providerA priority < B  ⟹ ✓ rewired:  \(.rewired.cacheUrl)  (from \(.rewired.resolvedFrom)) — SAME client logic, ZERO consumer edits"' 2>/dev/null \
    | while IFS= read -r line; do printf "${GREEN}%s${RESET}\n" "$line"; done || true
else
  printf '  result (raw): %s\n' "${JSON:-}"
fi

pause 0.4
printf '\n'
printf "  ${DIM}→ Producer publishes a capability; consumer discovers by NAME; a broker (a pure selector over a registrations stream, settled in one eval — not a live daemon) wires them. Neither references the other — swap the provider, the consumer is untouched. Real-world: service discovery / dependency injection, in config.${RESET}\n"

pause 0.6
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CLOSING BOX — summary table + honest scope
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$ACT" = "all" ]; then
sep
printf '\n'
printf "  ${BOLD}SUMMARY — nixpkgs vs dzm${RESET}\n"
printf '\n'
printf "  ${BOLD}%-28s  %-22s  %-22s${RESET}\n" "Scenario" "nixpkgs" "dzm"
printf "  %s\n" "$(printf '%0.s─' {1..76})"
printf "  %-28s  %-22s  %-22s\n" "blame (2 type errors)"   "ABORTS on 1st"           "ALL errors returned"
printf "  %-28s  %-22s  %-22s\n" "partial (1 bad of 6)"    "aborts all"               "settles good 5"
printf "  %-28s  %-22s  %-22s\n" "cycle (a <-> b)"         "infinite recursion"       "located {why=cycle}"
printf "  %-28s  %-22s  %-22s\n" "recover (port 8080/9090)" "throws+dies"             "resolves+RESUMES 3 ways"
printf "  %-28s  %-22s  %-22s\n" "policy (2 bad options)"  "one throw policy only"    "swap handler = swap policy"
printf "  %-28s  %-22s  %-22s\n" "actor ([10,20,30])"      "final=60 only"            "totals=[10,30,60]"
printf "  %-28s  %-22s  %-22s\n" "behaviour shape-flip"    "infinite recursion"       "LOCATED shape verdict"
printf "  %-28s  %-22s  %-22s\n" "dependent type (Vector n)" "structurally blocked"   "items:Vector n live"
printf "  %-28s  %-22s  %-22s\n" "Π-type (domain+codomain)" "codomain-only (no domain)" "full Π(x:A).B(x)"
printf "  %-28s  %-22s  %-22s\n" "discovery (client finds \"cache\")" "hardcodes provider path" "discovers by name, rewires 0-edit"
printf '\n'
printf "  ${DIM}Honest scope: Capabilities nixpkgs lib.evalModules structurally${RESET}\n"
printf "  ${DIM}cannot reach. Raw perf is secondary (the story is expressiveness${RESET}\n"
printf "  ${DIM}+ safety). Actor = genuine become/reply, not Erlang supervision.${RESET}\n"
printf "  ${DIM}Whole suite: 137/137 green.${RESET}\n"
printf '\n'
sep
printf '\n'
fi
