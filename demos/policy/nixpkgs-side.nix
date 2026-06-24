# demos/policy/nixpkgs-side.nix
# nixpkgs has ONE failure policy: throw. There is no warn-and-continue, no
# collect-all, no per-eval policy swap — the same config aborts, always.
let
  lib = import <nixpkgs/lib>;
  m = lib.evalModules {
    modules = [
      {
        options.port = lib.mkOption { type = lib.types.int; };
        options.host = lib.mkOption { type = lib.types.str; };
        config.port = "nope";
        config.host = "localhost";
      }
    ];
  };
in
{
  inherit (m.config) port host;
}
