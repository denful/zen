# demos/recover/nixpkgs-side.nix
# Same conflict: port defined 8080 in one module, 9090 in another.
# nixpkgs lib.evalModules throws "conflicting definition values" — fatal, no recovery.
let
  lib = import <nixpkgs/lib>;
  m = lib.evalModules {
    modules = [
      { options.port = lib.mkOption { type = lib.types.int; }; config.port = 8080; }
      { config.port = 9090; }
    ];
  };
in
m.config.port
