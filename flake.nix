{
  inputs = {
    nix-effects.url = "github:kleisli-io/nix-effects";
    nix-effects.flake = false;

    bend.url = "github:denful/bend";
    ned.url = "github:denful/ned";
  };

  outputs = inputs: {
    lib = import ./. { inherit inputs; };
  };
}
