let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  zen = import ../. { };
  N = 10000;

  dep = lib.types.submodule {
    options.name = lib.mkOption { type = lib.types.str; };
    options.version = lib.mkOption { type = lib.types.str; default = "latest"; };
  };

  pkg = lib.types.submodule {
    options.name = lib.mkOption { type = lib.types.str; };
    options.version = lib.mkOption { type = lib.types.str; default = "1.0"; };
    options.deps = lib.mkOption { type = lib.types.listOf dep; default = [ ]; };
  };

  base = { lib, ... }: {
    options.packages = lib.mkOption { type = lib.types.listOf pkg; default = [ ]; };
    options.tags = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    options.meta.count = lib.mkOption { type = lib.types.int; default = 0; };
    config.meta.count = N;
  };

  stressMods = map (i: { ... }: {
    config.packages = [
      {
        name = "pkg-${toString i}";
        version = "${toString i}.0";
        deps = [
          { name = "dep-a-${toString i}"; version = "1.0"; }
          { name = "dep-b-${toString i}"; version = "2.0"; }
          { name = "dep-c-${toString i}"; version = "3.0"; }
          { name = "dep-d-${toString i}"; version = "4.0"; }
          { name = "dep-e-${toString i}"; version = "5.0"; }
        ];
      }
    ];
    config.tags = [ "tag-${toString i}" ];
  }) (lib.range 1 N);

in
(zen.nixmod.evalModules { inherit lib; modules = [ base ] ++ stressMods; }).config
