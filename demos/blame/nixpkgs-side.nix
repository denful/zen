# demos/blame/nixpkgs-side.nix
# Two options (port, workers) both given wrong types.
# nixpkgs lib.evalModules aborts on the FIRST error only.
# Force m.config.port then m.config.workers to see both — but the first throw
# kills the process, so only ONE error is ever surfaced.
let
  lib = import <nixpkgs/lib>;
  m = lib.evalModules {
    modules = [
      {
        options.port = lib.mkOption { type = lib.types.int; };
        options.workers = lib.mkOption { type = lib.types.int; };
        config.port = "not-a-number";       # wrong: string, expects int
        config.workers = "also-not-a-number"; # wrong: string, expects int
      }
    ];
  };
in
# Accessing both — nixpkgs throws on the first, never reaching the second.
{ inherit (m.config) port workers; }
