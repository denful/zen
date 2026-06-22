# CHAIN fixture — zen-old (~/hk/zen, full-source-materialization engine).
#
# Same linear chain as chain-zen.nix (opt_k = opt_{k-1} + 1, opt_k == k), but
# expressed in ZEN-OLD's NATIVE idiom: the WHOLE-CONFIG function
# `(cfg: { config.<k> = cfg.<k-1> + 1; })`. zen-old's `nix/mods.nix` evaluates
# this by `plain = mapAttrs (_: getVal) srcs` — it MATERIALIZES every settled
# source for EVERY module's config (O(N) sources x O(N) modules = O(N^2)).
#
# This is the discriminator from the GOAL: zen-old's `mapAttrs getVal srcs`
# full-source materialization on a cross-option-edge config.
#
# zen-old's `run` takes a BARE module list (no { modules = ...; } wrapper) and
# uses `zen.merge`/`zen.types` (no `zen.m`/`zen.t` aliases).
#
# Invoke: nix-instantiate --eval --strict --argstr N 1000 chain-zen-old.nix
{ N }:
let
  zen = import /home/vic/hk/zen { };
  n = if builtins.isInt N then N else builtins.fromJSON N;

  nm = i: "o${toString i}";

  modules = builtins.genList (
    i:
    let
      key = nm i;
    in
    if i == 0 then
      {
        options.${key} = zen.opt zen.merge.unique zen.types.int;
        config.${key} = 0;
      }
    else
      let
        prev = nm (i - 1);
      in
      # WHOLE-CONFIG function: receives the full settled config projection `cfg`.
      (cfg: {
        options.${key} = zen.opt zen.merge.unique zen.types.int;
        config.${key} = cfg.${prev} + 1;
      })
  ) (n + 1);
in
zen.run modules
