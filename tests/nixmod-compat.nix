zen:
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  # Module 1: declares options.x (str, no default) and options.tags (listOf str)
  modOptions =
    { lib, ... }:
    {
      options.x = lib.mkOption { type = lib.types.str; };
      options.tags = lib.mkOption { type = lib.types.listOf lib.types.str; };
    };

  # Module 2: sets config.x = "hello"
  modConfigX = {
    config.x = "hello";
  };

  # Module 3: sets config.tags = ["a"]
  modConfigTags = {
    config.tags = [ "a" ];
  };

  modules = [
    modOptions
    modConfigX
    modConfigTags
  ];

  zen_config =
    (zen.nixmod.evalModules {
      inherit lib;
      modules = modules;
    }).config;

  lib_config =
    (lib.evalModules {
      modules = modules;
    }).config;
in
{
  nixmod-compat = {
    test_nixmod_compat_byte_identical = {
      expr = zen_config == lib_config;
      expected = true;
    };
  };
}
