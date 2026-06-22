zen:
# R1 — actor-cycle bridge: CONSTANT contribution + unknown-option blame.
#
# These exercise the bridge (`nix/bridge.nix`) wired into resolution
# (`nix/mods.nix` desugar + `nix/kernel.nix` aggregate). The literal-config
# path desugars to a constant Def, resolves through the option's lens, and
# aggregates to `{ right = config }`. A `config` target with no matching
# `options` declaration is blamed `unknown-option` and surfaces as `{ left }`.
let
  inherit (zen) bend;
in
{
  r1 = {

    # Positive: a single module / single option, constant config.
    #   zen.run { modules = [ { options.x = zen.opt zen.m.unique zen.t.int;
    #                           config.x = 1; } ]; }
    #   ⇒ { right = { x = 1; }; }
    test_R1_constant = {
      expr = zen.run {
        modules = [
          {
            options.x = zen.opt zen.m.unique zen.t.int;
            config.x = 1;
          }
        ];
      };
      expected = {
        right = {
          x = 1;
        };
      };
    };

    # Negative control: `config.y = 1` targets option `y`, but no module
    # declares `options.y` anywhere in the merged option set ⇒ left with
    # `why = "unknown-option"`. Proves target-key ⊆ merged-option-set fires.
    test_R1_unknown_option = {
      expr =
        let
          r = zen.run {
            modules = [
              {
                options.x = zen.opt zen.m.unique zen.t.int;
                config.x = 1;
                config.y = 1;
              }
            ];
          };
        in
        {
          isLeft = r ? left;
          why = r.left.y.left.why or null;
          got = r.left.y.left.got or null;
        };
      expected = {
        isLeft = true;
        why = "unknown-option";
        got = "y";
      };
    };

  };
}
