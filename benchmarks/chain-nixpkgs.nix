# CHAIN fixture — nixpkgs lib.evalModules.
#
# Same linear chain (opt_k = opt_{k-1} + 1, opt_k == k) in nixpkgs' module
# system. Each module reads the previous option off `config`:
#
#   config.o_k = config.o_{k-1} + 1
#
# nixpkgs resolves cross-option references through its fixpoint `config`; this is
# the third leg of the 3-way bench.
#
# Invoke: nix-instantiate --eval --strict --argstr N 1000 chain-nixpkgs.nix
{ N }:
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  n = if builtins.isInt N then N else builtins.fromJSON N;

  nm = i: "o${toString i}";

  modules = builtins.genList (
    i:
    let
      key = nm i;
    in
    (
      { config, ... }:
      {
        options.${key} = lib.mkOption { type = lib.types.int; };
        config.${key} = if i == 0 then 0 else config.${nm (i - 1)} + 1;
      }
    )
  ) (n + 1);
in
(lib.evalModules { inherit modules; }).config
