# demos/partial/nixpkgs-side.nix
# Same: one bad option (port) among good ones. Forcing both aborts on the bad —
# the good `host` is never returned. One bad option => deploy NOTHING.
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
