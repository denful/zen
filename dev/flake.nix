{
  outputs = _: { };

  inputs = {
    # Sole runtime dependency. dnzl re-exports ned/fx/bend + the actor vocab
    # (actor/reply/become/send/merge) and pulls its own transitive deps
    # (ned/bend/nix-effects) from the inputs set assembled here.
    dnzl.url = "github:denful/dnzl";
    dnzl.flake = false;

    # Transitive deps dnzl/default.nix reads off `inputs` directly.
    ned.url = "github:denful/ned";

    bend.url = "github:denful/bend";
    bend.flake = false;

    nix-effects.url = "github:kleisli-io/nix-effects";
    nix-effects.flake = false;

    # Bootstrap fetcher used by dev/with-inputs.nix.
    with-inputs.url = "github:denful/with-inputs";
    with-inputs.flake = false;
  };
}
