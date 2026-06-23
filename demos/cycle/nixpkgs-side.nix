# demos/cycle/nixpkgs-side.nix
# Mutual option reference: a depends on b, b depends on a.
# nixpkgs lib.evalModules → "infinite recursion encountered" (unlocated throw).
let
  lib = import <nixpkgs/lib>;
  m = lib.evalModules {
    modules = [
      {
        options.a = lib.mkOption { type = lib.types.int; };
        options.b = lib.mkOption { type = lib.types.int; };
        # mutual reference: a↔b cycle
        config.a = m.config.b;
        config.b = m.config.a;
      }
    ];
  };
in
# Force evaluation — triggers "infinite recursion encountered"
{ inherit (m.config) a b; }
