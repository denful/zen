zen:
let
  inherit (zen) bend ned opt;
  inherit (zen.merge) unique;

  intL = opt unique bend.int;
  strL = opt unique bend.str;

  # Reusable type: listOf int with concat merge strategy.
  # Each module contributes a list; all lists are concatenated in def order.
  listIntL = zen.types.listOf zen.types.int;

in
{
  kernel = {

    # T1: single option → right
    test-single-def-right = {
      expr = zen.run [
        {
          options.port = intL;
          config.port = 8080;
        }
      ];
      expected = bend.right { port = 8080; };
    };

    # T6: multiple options → right
    test-multi-option-right = {
      expr = zen.run [
        {
          options = {
            port = intL;
            host = strL;
          };
          config = {
            port = 8080;
            host = "localhost";
          };
        }
      ];
      expected = bend.right {
        port = 8080;
        host = "localhost";
      };
    };

    # T2: conflict — 2 modules set same option → left
    test-conflict-left = {
      expr =
        let
          result = zen.run [
            {
              options.port = intL;
              config.port = 8080;
            }
            { config.port = 9000; }
          ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T3: missing option — no def → left
    test-missing-left = {
      expr =
        let
          result = zen.run [ { options.port = intL; } ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T4: type error — string where int expected → left
    test-type-error-left = {
      expr =
        let
          result = zen.run [
            {
              options.port = intL;
              config.port = "not-an-int";
            }
          ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T5: fixpoint — hostMod reads cfg.port (plain value, no .right needed)
    test-fixpoint = {
      expr =
        let
          hostMod = cfg: {
            options.host = strL;
            config.host = "localhost:${toString (cfg.port or 80)}";
          };
        in
        zen.run [
          {
            options.port = intL;
            config.port = 8080;
          }
          hostMod
        ];
      expected = bend.right {
        port = 8080;
        host = "localhost:8080";
      };
    };

    # T7: partial errors — port conflict, host ok → left with mixed results
    test-partial-errors = {
      expr =
        let
          result = zen.run [
            {
              options = {
                port = intL;
                host = strL;
              };
              config.port = 8080;
            }
            { config.port = 9000; }
            { config.host = "localhost"; }
          ];
        in
        result ? left && result.left.port ? left && result.left.host ? right;
      expected = true;
    };

    # TC-A: cycle output-correctness (small N=3).
    # Three modules each contribute one element to the same listOf-int option.
    # cycle must concatenate them in def-visitation order: [10, 20, 30].
    # A wrong ordering, duplication, or drop would fail this assertion.
    # NEGATIVE CONTROL: temporarily replace the mode-E right-fold in
    # nix/kernel.nix with a reversed-index left-fold → test B catches the
    # stack overflow; this test catches wrong element order under any fold.
    test-cycle-small-n-concat = {
      expr = zen.run [
        { options.vals = listIntL; }
        { config.vals = [ 10 ]; }
        { config.vals = [ 20 ]; }
        { config.vals = [ 30 ]; }
      ];
      expected = bend.right { vals = [ 10 20 30 ]; };
    };

    # TC-B: cycle stack-safety discriminator (N=5000).
    # A single option receives 5000 contributions through cycle.
    # Under mode-E (right-fold lazy concat) this completes in O(1) Nix stack
    # depth per element → passes. Under a left-nested fold (mutant: replace the
    # `go` body with `(go (i+1)).concat (elemAt contribs i)`) forcing the head
    # recurses N deep → Nix max-call-depth → test FAILS (error).
    # PROVED NON-VACUOUS: the left-fold mutant causes "9995 duplicate frames
    # omitted … error: expected a set but found a function" (stack overflow
    # expressed as a type error after hitting max-call-depth).
    test-cycle-large-n-stack-safety =
      let
        cycleN = 5000;
        mods =
          [ { options.vals = listIntL; } ]
          ++ builtins.genList (i: { config.vals = [ i ]; }) cycleN;
        result = zen.run mods;
      in
      {
        expr = {
          isRight = result ? right;
          count = builtins.length result.right.vals;
          firstElem = builtins.head result.right.vals;
          lastElem = builtins.elemAt result.right.vals (cycleN - 1);
        };
        expected = {
          isRight = true;
          count = cycleN;
          firstElem = 0;
          lastElem = cycleN - 1;
        };
      };

    # TC-C: cycle empty-contributions branch.
    # A key that receives zero contributions from any def must yield the empty
    # stream (ned.st), which the unique merge strategy converts to a
    # `left { why = "required"; }` — the required-error identity for empty input.
    # A key that does receive a contribution must still resolve correctly.
    # NEGATIVE CONTROL: temporarily change the `if contribs == []` branch in
    # nix/kernel.nix to emit a non-empty stream → `absent` resolves to a
    # spurious value instead of `left.why = "required"` → test FAILS.
    test-cycle-empty-contribs-identity =
      let
        result = zen.run [
          {
            options.present = listIntL;
            options.absent = intL;
          }
          { config.present = [ 1 ]; }
        ];
      in
      {
        expr = {
          presentOk = result ? left && result.left.present ? right;
          absentErr = result ? left && result.left.absent ? left;
          absentWhy = result.left.absent.left.why or null;
        };
        expected = {
          presentOk = true;
          absentErr = true;
          absentWhy = "required";
        };
      };

  };
}
