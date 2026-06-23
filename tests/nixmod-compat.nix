zen:
let
  # Guard: check whether nixpkgs is present in NIX_PATH before importing it.
  # `builtins.findFile builtins.nixPath "nixpkgs"` is eval-time (not parse-time),
  # so `tryEval` can catch the "file 'nixpkgs' was not found" error cleanly.
  # When nixpkgs is absent the test degrades to a trivially-true/skipped case
  # without aborting the enclosing tests.nix eval.
  nixpkgsSearch = builtins.tryEval (builtins.findFile builtins.nixPath "nixpkgs");
  nixpkgsPresent = nixpkgsSearch.success;
in
if !nixpkgsPresent then
  {
    nixmod-compat = {
      # nixpkgs absent from NIX_PATH — skip (trivially true placeholder).
      test_nixmod_compat_byte_identical = {
        expr = true;
        expected = true;
      };
    };
  }
else
  let
    pkgs = import nixpkgsSearch.value { };
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
