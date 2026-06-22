#!/usr/bin/env bash
# Generate a zen CHAIN fixture as LITERAL Nix source for a given N.
#
# WHY source-gen (not a parametric .nix): zen's edge-local engine reads each
# config entry's dependency set via `builtins.functionArgs body`, which only
# sees LITERAL destructuring patterns `{ oK }: ...`. A programmatic
# `(args: args.${prev})` lambda has functionArgs == {} (empty inbox) and breaks.
# So the idiomatic zen chain MUST emit literal `{ o<k-1> }:` patterns. This
# generator does exactly that — it is the faithful zen encoding of the chain.
#
# Chain: o0 = 0 ; o_k = { o_{k-1} }: o_{k-1} + 1   =>  o_k == k.
#
# Usage: gen-zen-chain.sh N > chain-zen-gen-N.nix
set -euo pipefail
N="$1"
printf 'let\n'
printf '  zen = import /home/vic/hk/zen { };\n'
printf '  modules = [\n'
printf '    { options.o0 = zen.opt zen.m.unique zen.t.int; config.o0 = 0; }\n'
for ((k = 1; k <= N; k++)); do
  p=$((k - 1))
  printf '    { options.o%d = zen.opt zen.m.unique zen.t.int; config.o%d = { o%d }: o%d + 1; }\n' "$k" "$k" "$p" "$p"
done
printf '  ];\n'
printf 'in\n'
printf 'zen.run { inherit modules; }\n'
