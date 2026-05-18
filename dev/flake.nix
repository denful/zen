{
  outputs = _: { };

  inputs = {
    with-inputs.url = "github:denful/with-inputs";
    with-inputs.flake = false;

    ned.url = "github:denful/ned";
    bend.url = "github:denful/bend";
    import-tree.url = "github:denful/import-tree";

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix-effects.url = "github:kleisli-io/nix-effects";
    nix-effects.flake = false;
  };
}
