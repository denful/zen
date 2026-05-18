{
  inputs ? import ./dev/with-inputs.nix { },
  lib ? inputs.nixpkgs.lib,
  ...
}:
let
  bend = inputs.bend.lib;
  ned = inputs.ned.lib { inherit inputs; };
  fx = import inputs.nix-effects { inherit lib; };

  # Import all .nix files from nix/ directory
  readDirImports =
    dir:
    let
      files = builtins.readDir dir;
      fileList = builtins.filter (name: builtins.match ".*\\.nix$" name != null) (
        builtins.attrNames files
      );
      imports = builtins.map (name: import (dir + "/${name}") zen) fileList;
    in
    builtins.foldl' (acc: val: acc // val) { } imports;

  zen = {
    inherit fx ned bend;
  }
  // readDirImports ./nix;
in
zen
