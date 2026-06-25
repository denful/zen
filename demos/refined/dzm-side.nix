# demos/refined/dzm-side.nix
#
# Refinement type as a FIRST-CLASS, named, blame-carrying option type.
# The fx refined type names itself; dzm surfaces that name in LOCATED data
# (here via a small local lens). HONEST: this is a PREDICATE refinement
# (same check nixpkgs runs) — the win is the reified, located, named
# WITNESS, NOT a dependent type.
let
  zen = import ../../. { };

  # The refined Port type: .name = "Port", .check = Int ∩ [1024..65535]
  PortType = zen.fx.types.refined "Port" zen.fx.types.Int (n: n >= 1024 && n <= 65535);

  # A small local lens that surfaces the type's OWN name in the blame.
  # zen.satisfy discards the name; this 9-liner carries it forward so the
  # LOCATED left names "Port", not a generic "type-check failed".
  satisfyNamed = T: {
    get =
      v:
      if T.check v then
        zen.bend.right v
      else
        zen.bend.left {
          why = "refined";
          name = T.name;
          got = v;
        };
    set = _: zen.bend.right;
  };

  # port = 80 — below the 1024 floor: the located left names "Port" + got=80
  rejected = zen.run {
    modules = [
      {
        options.port = zen.opt zen.m.unique (satisfyNamed PortType);
        config.port = 80;
      }
    ];
  };

  # port = 8080 — valid ephemeral port: right { port = 8080 }
  accepted = zen.run {
    modules = [
      {
        options.port = zen.opt zen.m.unique (satisfyNamed PortType);
        config.port = 8080;
      }
    ];
  };

in
{
  # port=80 → located left; name="Port" and got=80 are DATA, not a string
  inherit rejected;
  # port=8080 → right { port=8080 }
  inherit accepted;
}
