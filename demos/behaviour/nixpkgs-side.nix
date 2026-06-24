# demos/behaviour/nixpkgs-side.nix
# Value-dependent option EXISTENCE: declare `turbo` ONLY when `enable` is true.
# nixpkgs option DECLARATIONS are static + resolved BEFORE the config fixpoint,
# so making a declaration depend on config throws "infinite recursion
# encountered" — nixpkgs' own diagnostic even says so and tells you to declare
# unconditionally and gate the EFFECT with mkIf (i.e. fall back to a value gate).
let
  lib = import <nixpkgs/lib>;
  m = lib.evalModules {
    modules = [
      (
        { config, lib, ... }:
        {
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          # config-dependent DECLARATION: turbo's EXISTENCE keyed on enable's VALUE.
          imports = lib.optionals config.enable [
            { options.turbo = lib.mkOption { type = lib.types.bool; }; }
          ];
        }
      )
      {
        enable = true;
        turbo = true;
      }
    ];
  };
in
# Force evaluation — triggers "infinite recursion encountered".
{
  inherit (m.config) enable turbo;
}
