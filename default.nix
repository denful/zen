{
  inputs ? import ./dev/with-inputs.nix { },
  lib ? inputs.nixpkgs.lib,
  ...
}:
let
  bend = inputs.bend.lib;
  ned = inputs.ned.lib { inherit inputs; };
  fx = import inputs.nix-effects { inherit lib; };
  readDirImports =
    dir:
    let
      names = builtins.filter (n: builtins.match ".*\\.nix$" n != null) (
        builtins.attrNames (builtins.readDir dir)
      );
    in
    builtins.foldl' (a: n: a // (import (dir + "/${n}") zen)) { } names;
  zen = {
    inherit fx ned bend;
  }
  // readDirImports ./nix;
in
zen
