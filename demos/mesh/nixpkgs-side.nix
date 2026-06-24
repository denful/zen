# demos/mesh/nixpkgs-side.nix
#
# Nixpkgs foil: two modules lib.mkForce the same option to different values.
# lib.evalModules throws "conflicting definition values" — fatal, eval dies.
# No negotiation seam, no handler, no dependent proof possible.
#
# Captured via builtins.tryEval so the file stays eval-clean while making the
# throw visible in the output attrset.
#
#   nix-instantiate --eval --strict demos/mesh/nixpkgs-side.nix
let
  lib = import <nixpkgs/lib>;
  # Attempt evalModules with two modules forcing `n` to different values.
  attempt = builtins.tryEval (
    (lib.evalModules {
      modules = [
        { options.n = lib.mkOption { type = lib.types.int; }; }
        { config.n = lib.mkForce 8080; }
        { config.n = lib.mkForce 9090; }
      ];
    }).config.n
  );
in {
  # success=false: the throw was caught — nixpkgs cannot negotiate, only die.
  success = attempt.success;
  # value is the fallback (false) when tryEval catches a throw.
  value   = attempt.value;
  note    = "lib.evalModules threw 'conflicting definition values'; tryEval caught it. No negotiation, no dependent proof — just a fatal throw.";
}
