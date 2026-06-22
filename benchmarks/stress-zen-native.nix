# Zen native — no nixpkgs import. Shows true eval performance.
let
  zen = import ../. { };
  N = 10000;

  mkOption =
    {
      type ? null,
      default ? null,
      ...
    }:
    {
      _type = "option";
      inherit type default;
    };
  types = {
    listOf = _: { name = "listOf"; };
    str = {
      name = "str";
    };
    int = {
      name = "int";
    };
    submodule = _: { name = "submodule"; };
  };
  lib = {
    inherit mkOption types;
    range = n: builtins.genList (i: i + 1) n;
  };

  base =
    { lib, ... }:
    {
      options.packages = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule { });
        default = [ ];
      };
      options.tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      options.meta.count = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      config.meta.count = N;
    };

  stressMods = map (
    i:
    { ... }:
    {
      config.packages = [
        {
          name = "pkg-${toString i}";
          version = "${toString i}.0";
          deps = [
            {
              name = "dep-a-${toString i}";
              version = "1.0";
            }
            {
              name = "dep-b-${toString i}";
              version = "2.0";
            }
            {
              name = "dep-c-${toString i}";
              version = "3.0";
            }
            {
              name = "dep-d-${toString i}";
              version = "4.0";
            }
            {
              name = "dep-e-${toString i}";
              version = "5.0";
            }
          ];
        }
      ];
      config.tags = [ "tag-${toString i}" ];
    }
  ) (lib.range N);

in
(zen.nixmod.evalModules {
  inherit lib;
  modules = [ base ] ++ stressMods;
}).config
