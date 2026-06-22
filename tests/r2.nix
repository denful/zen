zen:
# R2 — derived projection (REAL) + accumulating, located blame.
#
# R1 wired the bridge's function-path STRUCTURALLY (inbox = `functionArgs`) but
# left the body resolution a stub. R2 makes `config.<name> = { deps... }: expr`
# actually RESOLVE: the bridge applies the body to a projection carrying EXACTLY
# its `functionArgs` deps' SETTLED VALUES (edge-local), and the type lens runs on
# the settled value. R2 also turns blame ACCUMULATING (every failing option's
# error, not first-only) and LOCATED (`{ path, file, got, why }`).
#
# These four tests are the cheat-proof oracles for the rung:
#   - test_R2_derived           — derived projection produces the right value.
#   - test_R2_edge_local        — BEHAVIORAL: resolving `b` does NOT force a
#                                 divergent sibling `c` (kills all-settled impls).
#   - test_blame_accumulates    — TWO independent faults ⇒ BOTH in `left.errors`
#                                 (kills first-fail/short-circuit impls).
#   - test_R2_type_mismatch     — wrong-typed value ⇒ located `why = "type"` blame.
let
  inherit (zen) ned;
  inherit (builtins)
    mapAttrs
    head
    length
    any
    ;
in
{
  r2 = {

    # --- POSITIVE: derived projection resolves edge-local settled values. ---
    # options.a, options.b : int. config.a = 2 (literal). config.b = {a}: a + 40.
    # `b`'s inbox is exactly {a} (functionArgs); the bridge applies the body to
    # a's SETTLED value (2), so b contributes 42, type-checks as int, and the
    # aggregate is { right = { a = 2; b = 42; } }. Proves the R1 stub is now a
    # real resolution.
    test_R2_derived = {
      expr = zen.run {
        modules = [
          {
            options.a = zen.opt zen.m.unique zen.t.int;
            options.b = zen.opt zen.m.unique zen.t.int;
            config.a = 2;
            config.b = { a }: a + 40;
          }
        ];
      };
      expected = {
        right = {
          a = 2;
          b = 42;
        };
      };
    };

    # --- BEHAVIORAL EDGE-LOCALITY (the discriminator). ---
    # WHY THIS DISCRIMINATES all-settled from edge-local:
    #   `config.b = {a}: a` depends ONLY on a. A separate option `c` has a derived
    #   config whose VALUE is `throw "c was forced!"` — i.e. forcing c's settled
    #   value DIVERGES. b does NOT depend on c.
    #   * Edge-local impl (CORRECT): b's projection reads ONLY `srcs.a` (its
    #     functionArgs inbox), never `srcs.c`. So b settles to a's value (2) and
    #     c's `throw` is NEVER triggered. This test extracts b's settled either
    #     ALONE (mirroring kernel.run's per-option recovery, but only for b), so
    #     the divergent c is never demanded.
    #   * All-settled impl (WRONG): would build b's dep projection from ALL of
    #     `srcs` (the full settled option set), forcing `srcs.c`'s value → the
    #     `throw` fires → evaluating b ERRORS. Such an impl CANNOT make this test
    #     pass: b's result is entangled with c's divergence.
    #   Note `c` is itself a derived `{a}: throw ...` (so it is a real function-path
    #   contribution, not a literal), making the only thing that saves b the
    #   edge-local restriction of b's OWN inbox to {a}. The cycle constructs c's
    #   Def lazily (its `.value` thunk is the `throw`); only READING c's settled
    #   value forces it — which an edge-local b never does.
    test_R2_edge_local =
      let
        params = zen.fromMods [
          {
            options.a = zen.opt zen.m.unique zen.t.int;
            options.b = zen.opt zen.m.unique zen.t.int;
            options.c = zen.opt zen.m.unique zen.t.int;
            config.a = 2;
            config.b = { a }: a;
            config.c = { a }: throw "c was forced!";
          }
        ];
        inherit (params) lens defs;
        drivers = mapAttrs (_: _: ned.collect-d) lens;
        sinks = ned.run drivers (zen.cycle lens defs);
        # Recover ONLY b's settled either — never demands c.
        bEither = head ((ned.collect-d sinks.b (lens.b)).toList);
      in
      {
        expr = bEither;
        expected = {
          right = 2;
        };
      };

    # --- CRITICAL: accumulating blame across independent faults. ---
    # ONE module with TWO simultaneous, independent faults:
    #   * config.p = "nope" against options.p = int  → a TYPE error on p.
    #   * config.q = 1 with NO options.q             → an UNKNOWN-OPTION error on q.
    # Accumulating aggregate ⇒ `left.errors` contains BOTH blame records (length
    # >= 2), each located by `path` + `why`. A first-fail/short-circuit impl that
    # returns only the first error CANNOT pass: it would yield length 1 and miss
    # one of the two whys.
    test_blame_accumulates =
      let
        r = zen.run {
          modules = [
            {
              options.p = zen.opt zen.m.unique zen.t.int;
              config.p = "nope";
              config.q = 1;
            }
          ];
        };
        errs = r.left.errors or [ ];
        hasType = any (e: (e.why or null) == "type" && (e.path or null) == "p") errs;
        hasUnknown = any (e: (e.why or null) == "unknown-option" && (e.path or null) == "q") errs;
      in
      {
        expr = {
          isLeft = r ? left;
          errorCount = length errs;
          atLeastTwo = length errs >= 2;
          bothPresent = hasType && hasUnknown;
        };
        expected = {
          isLeft = true;
          errorCount = 2;
          atLeastTwo = true;
          bothPresent = true;
        };
      };

    # --- NEGATIVE CONTROL: wrong-typed value ⇒ located type blame. ---
    # config.p = "nope" against options.p = int ⇒ left with why = "type", and the
    # blame is LOCATED (got = the offending value, path = the option name).
    test_R2_type_mismatch =
      let
        r = zen.run {
          modules = [
            {
              options.p = zen.opt zen.m.unique zen.t.int;
              config.p = "nope";
            }
          ];
        };
      in
      {
        expr = {
          isLeft = r ? left;
          why = r.left.p.left.why or null;
          got = r.left.p.left.got or null;
          path = r.left.p.left.path or null;
        };
        expected = {
          isLeft = true;
          why = "type";
          got = "nope";
          path = "p";
        };
      };

  };
}
