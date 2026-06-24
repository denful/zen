zen:
# R9 — TRUE Π-types (dependent FUNCTION types) wired through `zen.run` options
# (spec §8). The companion to R8's Σ-types: where R8 carried a dependent PAIR
# (`items :: Vector n`), R9 carries a dependent FUNCTION — one option holds a
# FUNCTION, another holds the ARGUMENT it is applied to, and the function's
# codomain TYPE is a function of the argument's VALUE.
#
# THE nixpkgs GAP (real, structural): `lib.types.functionTo retType` has a
# SINGLE slot — the codomain (return type). It wraps the function and checks
# RESULTS; the DOMAIN (input type) is inexpressible (no slot), and a
# value-dependent codomain (`(n:Int) -> Vector n`) is doubly inexpressible. The
# MLTT answer `Π(x:A).B(x)` states BOTH the domain A and a codomain family B(x).
#
# HOW fx Π checks a raw Nix lambda (verified, evidence-before-claim — see
# nix-effects/src/types/dependent.nix:120-190):
#   - The pure guard `fx.types.check piT f` is ONLY `builtins.isFunction`
#     (dependent.nix:1306) — a raw lambda has no type annotation, so the guard
#     CANNOT see the domain/codomain (a wrong-typed lambda still passes it).
#   - The domain+codomain are verified at the ELIMINATION site via
#     `pi.checkAt f arg` (dependent.nix:157-190): it APPLIES f to a concrete
#     argument, sending a `typeCheck` effect for `arg : domain`, then (on pass)
#     for `f arg : codomain arg`. The codomain is `codomain arg` — a genuine
#     function of the input VALUE. `zen.pitype` RUNS that effectful elimination
#     through an error-collecting handler and collapses it to a located Either,
#     so the whole-config `check` seam (kernel.nix:327/395) sees `right`/`left`.
#
# OBJECTIVE ORACLE per test below:
#   - domain:   Int arg → right; wrong-type arg → LOCATED left {site="domain"}.
#   - codomain: result inhabits B(arg) → right; wrong result → LOCATED left
#               {site="codomain"} naming the fx type B(arg) at the resolved arg.
#   - dependent fn: mkVec 3 len-3 → right; a fn returning len-2 → left at n=3.
#   - NEGATIVE CONTROL: a mutant (len-2 fn at n=3) MUST reject.
#   - DEPENDENCE: change `n`, the required length changes (len-2 fn ACCEPTED at
#     n=2, REJECTED at n=3) — proving the codomain references the arg's VALUE.
let
  inherit (zen) fx;

  IntT = fx.types.Int;

  # The dependent codomain family: fx's canonical length-indexed vector at the
  # argument value. `vecAt n = Vector Int n` — an MLTT dependent type object
  # (nix-effects types.dependent), not a hand-rolled predicate.
  vecAt = n: (fx.types.Vector IntT).apply n;

  # (1) DOMAIN demo: a function option `f :: Int → Int` applied to a sample
  #     input option `x`. nixpkgs `functionTo` cannot constrain the domain.
  runDom =
    fnVal: argVal:
    zen.run {
      lens = {
        f = zen.types.any;
        x = zen.types.any;
      };
      defs = [
        (zen.def {
          f = fnVal;
          x = argVal;
        })
      ];
      check = zen.pitype {
        fn = "f";
        arg = "x";
        domain = IntT;
        codomain = _: IntT;
      };
    };

  # (2) DEPENDENT FUNCTION demo: `mkVec :: (n:Int) → Vector n`. The result TYPE
  #     is computed from the argument VALUE via the fx Vector family.
  runVec =
    fnVal: nVal:
    zen.run {
      lens = {
        mkVec = zen.types.any;
        n = zen.types.any;
      };
      defs = [
        (zen.def {
          mkVec = fnVal;
          n = nVal;
        })
      ];
      check = zen.pitype {
        fn = "mkVec";
        arg = "n";
        domain = IntT;
        codomain = vecAt;
      };
    };

  double = x: x * 2;
  mkVecOk = n: builtins.genList (i: i) n; # returns a length-n vector
  mkVecBad2 = _: [
    1
    2
  ]; # ALWAYS returns length-2 (ignores n)
in
{
  r10 = {

    # === DOMAIN: correct → right ===========================================
    # f : Int → Int applied to 21 (an Int): `21 : Int` ∧ `double 21 = 42 : Int`.
    # (The settled `right` carries the function value `f`, which Nix cannot
    # compare for equality — so we assert `right`-ness plus the comparable arg.)
    test_R9_domain_correct_settles_right = {
      expr =
        let
          r = runDom double 21;
        in
        {
          isRight = r ? right;
          x = r.right.x or null;
          # The function inhabits the type and IS preserved in the config.
          fIsFn = builtins.isFunction (r.right.f or null);
        };
      expected = {
        isRight = true;
        x = 21;
        fIsFn = true;
      };
    };

    # === DOMAIN: wrong-type ARGUMENT → LOCATED left ========================
    # f : Int → Int applied to "no" (a String): the DOMAIN check fails. This is
    # the capability nixpkgs `functionTo` STRUCTURALLY lacks — it can only check
    # the RESULT, never reject a wrong-type argument. Blame is located at the
    # `x` option with site="domain".
    test_R9_domain_wrong_arg_located_left = {
      expr =
        let
          r = runDom double "no";
        in
        {
          isLeft = r ? left;
          why = r.left.why or null;
          site = r.left.site or null;
          path = r.left.path or null;
          argValue = r.left.argValue or null;
        };
      expected = {
        isLeft = true;
        why = "pitype";
        site = "domain";
        path = "x";
        argValue = "no";
      };
    };

    # === CODOMAIN: wrong RESULT type → LOCATED left ========================
    # f applied to a valid Int arg, but f returns a String when Int is expected:
    # the CODOMAIN check fails. Blame is located at the `f` option (its result
    # was ill-typed) with site="codomain". functionTo CAN catch this one — but
    # only because it is the codomain; the point is dzm catches BOTH ends.
    test_R9_codomain_wrong_result_located_left = {
      expr =
        let
          r = runDom (_: "not-an-int") 21;
        in
        {
          isLeft = r ? left;
          site = r.left.site or null;
          path = r.left.path or null;
        };
      expected = {
        isLeft = true;
        site = "codomain";
        path = "f";
      };
    };

    # === DEPENDENT FUNCTION: mkVec 3, length-3 result → right =============
    # mkVec applied to n=3 returns [0 1 2] (length 3); the codomain at n=3 is
    # `Vector[3, Int]` (computed from the VALUE 3), which accepts it. (The
    # function value cannot be equality-compared — assert `right` + the arg +
    # that the produced result actually has the codomain-required length.)
    test_R9_dependent_correct_settles_right = {
      expr =
        let
          r = runVec mkVecOk 3;
        in
        {
          isRight = r ? right;
          n = r.right.n or null;
          producedLen = builtins.length ((r.right.mkVec or (_: [ ])) 3);
        };
      expected = {
        isRight = true;
        n = 3;
        producedLen = 3;
      };
    };

    # === DEPENDENT FUNCTION: wrong-length result → LOCATED left ============
    # A function that returns length-2 regardless of n, applied at n=3: the
    # codomain `Vector[3, Int]` rejects the length-2 result. The located left's
    # `expected` NAMES the fx MLTT type at the RESOLVED argument — proving the
    # type was computed from n's value, not a constant.
    test_R9_dependent_wrong_length_named_fx_type = {
      expr =
        let
          r = runVec mkVecBad2 3;
        in
        {
          isLeft = r ? left;
          site = r.left.site or null;
          expected = r.left.expected or null;
        };
      expected = {
        isLeft = true;
        site = "codomain";
        expected = "Vector[3, Int]";
      };
    };

    # === NEGATIVE CONTROL — the mutant MUST reject ========================
    # The oracle's mandated mutant: a function returning length-2 applied at
    # n=3. A check that ignored `n` (e.g. constant `length > 0`) would accept
    # this; the dependent Π rejects it. `expected = true` (it IS a left).
    test_R9_negative_control_mutant_rejects = {
      expr = (runVec mkVecBad2 3) ? left;
      expected = true;
    };

    # === DEPENDENCE — the codomain depends on the ARG's VALUE =============
    # SAME function (mkVecBad2, always length-2): ACCEPTED at n=2, REJECTED at
    # n=3. If the required length were a constant, both would agree; they do not
    # — the codomain is `Vector[n]`, computed from n's value. The correct fn is
    # accepted at both indices that match its output length.
    test_R9_codomain_depends_on_value = {
      expr = {
        len2_at_n2_ok = (runVec mkVecBad2 2) ? right;
        len2_at_n3_rejected = (runVec mkVecBad2 3) ? left;
        len3_at_n3_ok = (runVec mkVecOk 3) ? right;
        len3_at_n2_rejected =
          (runVec (_: [
            0
            1
            2
          ]) 2) ? left;
      };
      expected = {
        len2_at_n2_ok = true;
        len2_at_n3_rejected = true;
        len3_at_n3_ok = true;
        len3_at_n2_rejected = true;
      };
    };

    # === Π elimination at the fx layer (unit-level, no zen) ================
    # Pins the load-bearing fact directly on fx: a Π-type's domain+codomain are
    # checked at the ELIMINATION site `checkAt f arg`, the codomain being
    # `codomain arg` (a function of the VALUE). This isolates the fx→dzm boundary
    # so a regression there cannot mask a broken type. The pure guard `check` is
    # ONLY isFunction (a wrong-typed lambda passes it) — proving WHY `zen.pitype`
    # must run the effectful elimination, not the pure guard.
    test_R9_fx_pi_elimination_is_value_dependent = {
      expr =
        let
          piVec = fx.types.Pi {
            domain = IntT;
            codomain = vecAt;
            universe = 0;
          };
          # All-pass handler: .state is the conjunction of every typeCheck.
          runAllPass =
            comp:
            (fx.handle {
              handlers.typeCheck =
                { param, state }:
                let
                  passed = param.type.check param.value;
                in
                {
                  resume = passed;
                  state = state && passed;
                };
              state = true;
            } comp).state;
        in
        {
          # Pure guard is blind: a length-2-returning lambda passes `check`
          # (it IS a function) — the guard sees no codomain.
          guard_blind = fx.types.check piVec mkVecBad2;
          # Elimination at n=3: correct length-3 fn passes, length-2 fn fails.
          elim_ok = runAllPass (piVec.checkAt mkVecOk 3);
          elim_bad = runAllPass (piVec.checkAt mkVecBad2 3);
          # Same length-2 fn: passes elimination at n=2.
          elim_dep = runAllPass (piVec.checkAt mkVecBad2 2);
        };
      expected = {
        guard_blind = true;
        elim_ok = true;
        elim_bad = false;
        elim_dep = true;
      };
    };

  };
}
