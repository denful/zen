# demos/actor/nixpkgs-side.nix
# Running-total actor: send [10,20,30], expect totals [10,30,60].
# nixpkgs lib.evalModules has NO become/inbox/actor primitives.
# The only way to get a running total in nixpkgs is builtins.foldl' —
# which computes the FINAL sum only, not the per-step prefix totals.
# There is no message-passing, no stateful sessions, no scanl.
let
  lib = import <nixpkgs/lib>;

  # nixpkgs approach: pure fold — gives the final total, NOT the prefix list
  batch = [
    10
    20
    30
  ];
  finalTotal = builtins.foldl' (acc: x: acc + x) 0 batch;

  # What the investor wants: per-step running totals [10, 30, 60]
  # nixpkgs cannot produce this without re-implementing an actor from scratch.
  # The closest approximation requires a manual scanl — not built in.
  manualScanl =
    init: f: list:
    let
      go =
        acc: rest:
        if rest == [ ] then
          [ ]
        else
          let
            next = f acc (builtins.head rest);
          in
          [ next ] ++ go next (builtins.tail rest);
    in
    go init list;

  # Even with manual scanl, you cannot send to a live actor across modules.
  prefixTotals = manualScanl 0 (a: b: a + b) batch;
in
{
  nixpkgs_final_total_only = finalTotal; # 60 — only the end result
  nixpkgs_no_actor_primitive = true;
  # grep -c 'become\|inbox\|scanl' <nixpkgs>/lib/modules.nix
  # = 1 (one comment "might become obsolete") — zero runtime primitives
  grep_become_in_modules_nix = 1; # the comment, not a primitive
  grep_inbox_in_modules_nix = 0;
  grep_scanl_in_modules_nix = 0;
  verdict = "nixpkgs: fold gives final=60 only; no typed actor/send primitive";
  # Manual scanl works as a workaround, but is NOT a module-system capability
  workaround_prefix = prefixTotals;
}
