zen:
# R4 — merge strategies over the priority/order-FILTERED survivors +
# multi-module assembly.
#
# R3 made priority a PRE-FILTER (api.nix resolveStage): the survivors that
# reach a merge strategy are already (a) filtered to the numerically-lowest
# priority class and (b) sorted by the order axis. R4 confirms each strategy
# (`unique`/`first`/`last`/`concat`/`attrs`) consumes that survivor list
# correctly, and that a LIST of `{ options, config }` modules assembles into
# one config via `fromMods` — an option declared in one module being read,
# EDGE-LOCALLY, by a derived config in ANOTHER module across the cycle.
#
# The three oracles:
#   - test_R4_inter_module : b (module2) reads a (module1) across the cycle,
#                            forcing ONLY its dep ⇒ { right = { a=5; b=15; } }.
#   - test_R4_strategies   : unique(single)/first/last/concat/attrs each
#                            resolve as specified over multi-def survivors.
#                            first = order-first survivor; last = order-last
#                            survivor (priority can no longer distinguish
#                            same-class survivors, so position over the
#                            order-sorted list is the meaningful first/last).
#   - test_R4_missing_required : a required option (no default, no config) ⇒
#                            a per-option `left` carrying zen's existing
#                            required-missing shape (`why = "required"`).
let
  inherit (zen) bend;
in
{
  r4 = {

    # === test_R4_inter_module — multi-module assembly + edge-local read ======
    # module1 DECLARES + SETS `a`; module2 DECLARES `b` whose derived config
    # `{a}: a + 10` reads `a` — an option declared in a DIFFERENT module —
    # across the actor cycle. `fromMods` merges both option sets into one lens
    # and both config sets into the def graph; b's inbox is EXACTLY {a}
    # (functionArgs), so the read forces only a, edge-locally.
    #   zen.run { modules = [module1 module2]; } ⇒ { right = { a=5; b=15; } }
    test_R4_inter_module =
      let
        module1 = {
          options.a = zen.opt zen.m.unique zen.t.int;
          config.a = 5;
        };
        module2 = {
          options.b = zen.opt zen.m.unique zen.t.int;
          config.b = { a }: a + 10;
        };
      in
      {
        expr = zen.run {
          modules = [
            module1
            module2
          ];
        };
        expected = {
          right = {
            a = 5;
            b = 15;
          };
        };
      };

    # === test_R4_strategies — every strategy over multi-def survivors ========
    # Each option carries TWO same-priority (bare/order-tagged) defs so both
    # survive the priority filter and reach the strategy as a real multi-def
    # survivor list, order-sorted:
    #   unique : a SINGLE def survives ⇒ the bare value (9).
    #   first  : mkBefore(order 500) then mkAfter(order 1500) ⇒ order-FIRST = 1.
    #   last   : same two defs ⇒ order-LAST = 2 (NOT the priority-first; priority
    #            is identical, so position over the order-sorted list decides).
    #   concat : two list defs ⇒ concatenated in order ⇒ [1 2].
    #   attrs  : two attrset defs ⇒ right-biased merge ⇒ { x=1; y=2; }.
    test_R4_strategies =
      let
        run =
          strat: t: cfg:
          zen.run {
            modules = [
              {
                options.v = zen.opt strat t;
                config.v = cfg;
              }
            ];
          };
        uniqR = run zen.m.unique zen.t.int 9;
        firstR = run zen.m.first zen.t.int (
          zen.mkMerge [
            (zen.mkBefore 1)
            (zen.mkAfter 2)
          ]
        );
        lastR = run zen.m.last zen.t.int (
          zen.mkMerge [
            (zen.mkBefore 1)
            (zen.mkAfter 2)
          ]
        );
        concatR = run zen.m.concat (bend.each bend.int) (
          zen.mkMerge [
            [ 1 ]
            [ 2 ]
          ]
        );
        attrsR = run zen.m.attrs (bend.eachValue bend.int) (
          zen.mkMerge [
            { x = 1; }
            { y = 2; }
          ]
        );
      in
      {
        expr = {
          unique = uniqR.right.v or null;
          first = firstR.right.v or null;
          last = lastR.right.v or null;
          concat = concatR.right.v or null;
          attrs = attrsR.right.v or null;
        };
        expected = {
          unique = 9;
          first = 1;
          last = 2;
          concat = [
            1
            2
          ];
          attrs = {
            x = 1;
            y = 2;
          };
        };
      };

    # === NEGATIVE CONTROL: test_R4_missing_required =========================
    # A required option (no `withDefault`, no `config` contribution anywhere)
    # has an EMPTY survivor list reaching its strategy. `withRequired`
    # (merge.nix) maps `[] -> bend.left { why = "required"; }` — zen's existing
    # required-missing shape (matched, not renamed, so `kernel.test-missing-left`
    # stays green). The option settles to a per-option `left` whose
    # `why = "required"`, and the aggregate is a `{ left }`.
    test_R4_missing_required =
      let
        r = zen.run {
          modules = [
            {
              options.needed = zen.opt zen.m.unique zen.t.int;
              # no config.needed anywhere ⇒ required + missing.
            }
          ];
        };
      in
      {
        expr = {
          isLeft = r ? left;
          settledLeft = r.left.needed or { } ? left;
          why = r.left.needed.left.why or null;
        };
        expected = {
          isLeft = true;
          settledLeft = true;
          why = "required";
        };
      };

  };
}
