zen:
# R8 — TRUE dependent types wired through a `zen.run` option (spec §8).
#
# The investor demo: one option's TYPE depends on another option's VALUE —
# `n :: Int` and `items :: Vector n` (a list of EXACTLY `n` elements). nixpkgs
# `lib.evalModules` STRUCTURALLY cannot express this: a `type` there is a fixed
# value computed before any option's value is known; there is no seam where one
# option's resolved value parameterises another option's type.
#
# dzm carries it because the `check` hook (kernel.nix:327/395) receives the WHOLE
# settled config, so a genuine Martin-Löf Σ-type can live there. `zen.deptype`
# threads fx's ACTUAL `Sigma`/`Vector` constructor (nix-effects types.dependent):
# the second component is a TYPE FAMILY `snd :: indexValue -> Type`, so the type
# of `items` is LITERALLY a function of the value of `n` — not a hand-rolled
# boolean. This is an MLTT dependent type, not merely a cross-field predicate.
#
# OBJECTIVE ORACLE per test below:
#   - correct (length == n)  → `bend.right cfg`        (the Σ introduction form)
#   - wrong   (length != n)  → LOCATED `bend.left {…}` (why/path/index — not a throw)
#   - NEGATIVE CONTROL: a mutant pair (n=3, length 2) MUST reject.
#   - DEPENDENCE: change `n`, the required length changes (n=2 accepts len 2,
#     rejects len 3) — proving the type references `n`'s value, not a constant.
let
  inherit (zen) fx;
  H = fx.types.hoas;

  # The dependent family written two ways, both genuine fx MLTT type objects.

  # (a) hand-built Σ family: snd n = { v | isList v ∧ length v == n }. The TYPE
  #     is a function of the index value n (Martin-Löf 1984 Σ second component).
  sizedVec =
    n:
    fx.types.mkType {
      name = "Vector[n=${toString n}]";
      kernelType = H.any;
      guard = v: builtins.isList v && builtins.length v == n;
    };

  # (b) fx's NAMED dependent constructor: `Vector Int n` is the canonical
  #     length-indexed vector from nix-effects types.dependent — the textbook
  #     MLTT example, applied at the index value.
  vectorIntAt = n: (fx.types.Vector fx.types.Int).apply n;

  # A `zen.run` over `n` (int) and `items` (list), with a dependent-type check
  # binding `items`'s type to `n`'s value via `zen.deptype`.
  runDep =
    { snd }:
    nVal: itemsVal:
    zen.run {
      lens = {
        n = zen.types.int;
        items = zen.types.listOf zen.types.any;
      };
      defs = [
        (zen.def {
          n = nVal;
          items = itemsVal;
        })
      ];
      check = zen.deptype {
        index = "n";
        depends = "items";
        fst = fx.types.Int;
        inherit snd;
      };
    };

  runSized = runDep { snd = sizedVec; };
  runVector = runDep { snd = vectorIntAt; };
in
{
  r8 = {

    # === CORRECT → right (Σ introduction form) ==============================
    # n = 3, items length 3 → the pair inhabits the Σ-type → `right cfg`.
    test_R8_correct_settles_right = {
      expr = runSized 3 [
        "a"
        "b"
        "c"
      ];
      expected = zen.bend.right {
        n = 3;
        items = [
          "a"
          "b"
          "c"
        ];
      };
    };

    # === WRONG length → LOCATED left (not a throw) =========================
    # n = 3, items length 2 → reject with a located `left` carrying the blame
    # tag, the offending option path, and the index value it was checked against.
    test_R8_wrong_length_settles_located_left = {
      expr =
        let
          r = runSized 3 [
            "a"
            "b"
          ];
        in
        {
          isLeft = r ? left;
          why = r.left.why or null;
          path = r.left.path or null;
          indexValue = r.left.indexValue or null;
          got = r.left.got or null;
        };
      expected = {
        isLeft = true;
        why = "deptype";
        path = "items";
        indexValue = 3;
        got = [
          "a"
          "b"
        ];
      };
    };

    # === NEGATIVE CONTROL — the mutant MUST reject =========================
    # The oracle's mandated mutant: n=3 but items length 2. A check that ignored
    # `n` (e.g. a constant `length > 0`) would accept this; the dependent type
    # rejects it. `expected = true` (it IS a left).
    test_R8_negative_control_mutant_rejects = {
      expr =
        (runSized 3 [
          "a"
          "b"
        ]) ? left;
      expected = true;
    };

    # === DEPENDENCE — the TYPE depends on n's VALUE =======================
    # Same length-2 items: ACCEPTED when n=2, REJECTED when n=3. Same length-3
    # items: REJECTED when n=2, ACCEPTED when n=3. If `items`'s required length
    # were a constant, all four would agree; they do not — the type is `snd n`.
    test_R8_type_depends_on_value = {
      expr = {
        n2_len2_ok =
          (runSized 2 [
            "a"
            "b"
          ]) ? right;
        n2_len3_rejected =
          (runSized 2 [
            "a"
            "b"
            "c"
          ]) ? left;
        n3_len2_rejected =
          (runSized 3 [
            "a"
            "b"
          ]) ? left;
        n3_len3_ok =
          (runSized 3 [
            "a"
            "b"
            "c"
          ]) ? right;
      };
      expected = {
        n2_len2_ok = true;
        n2_len3_rejected = true;
        n3_len2_rejected = true;
        n3_len3_ok = true;
      };
    };

    # === fx NAMED `Vector` constructor threads the same seam ===============
    # Using fx.types.Vector (the canonical length-indexed vector) as the family:
    # correct → right; the located-left's `expected` names the fx type at the
    # resolved index (`Vector[3, Int]`), proving the fx MLTT object is what runs.
    test_R8_named_vector_correct_right = {
      expr = runVector 3 [
        1
        2
        3
      ];
      expected = zen.bend.right {
        n = 3;
        items = [
          1
          2
          3
        ];
      };
    };

    test_R8_named_vector_wrong_left_names_fx_type = {
      expr =
        let
          r = runVector 3 [
            1
            2
          ];
        in
        {
          isLeft = r ? left;
          expected = r.left.expected or null;
        };
      expected = {
        isLeft = true;
        expected = "Vector[3, Int]";
      };
    };

    # === Σ value-dependence at the fx layer (unit-level, no zen) ===========
    # Pins the underlying invariant directly on fx: `fx.types.check (Sigma …)`
    # over a pair where snd's type is `snd fst`. This is the load-bearing fact
    # the whole demo rests on; isolating it guards against a regression in the
    # fx→dzm boundary masking a broken type.
    test_R8_fx_sigma_value_dependent = {
      expr =
        let
          Sig = fx.types.Sigma {
            fst = fx.types.Int;
            snd = sizedVec;
            universe = 0;
          };
        in
        {
          good = fx.types.check Sig {
            fst = 3;
            snd = [
              1
              2
              3
            ];
          };
          bad = fx.types.check Sig {
            fst = 3;
            snd = [
              1
              2
            ];
          };
          dep_n2 = fx.types.check Sig {
            fst = 2;
            snd = [
              1
              2
            ];
          };
        };
      expected = {
        good = true;
        bad = false;
        dep_n2 = true;
      };
    };

  };
}
