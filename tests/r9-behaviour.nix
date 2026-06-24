zen:
# R9 — value-dependent option EXISTENCE (the actor `become` demo, spec §8).
#
# An `enable :: Bool` option whose VALUE flips which options the module accepts —
# like an actor `become` swapping behaviour (and its message interface). The
# accepted config SHAPE is `snd enable`:
#   enable = true  → behaviour A: {turbo, maxSpeed} ARE part of the interface
#                    (present = well-formed; absent = a LOCATED left).
#   enable = false → behaviour B: those options are NOT part of the interface
#                    (absent = well-formed; present = a LOCATED left).
#
# The dependent type is fx's ACTUAL `Sigma` over `Bool` with LARGE ELIMINATION —
# `Σ (b:Bool) (snd b)`, the record TYPE chosen by casing the value (`snd true`
# admits the fields PRESENT, `snd false` admits them ABSENT). Threaded through
# dzm's whole-config `check` seam by `zen.depshape`. Errors are DATA, never an
# abort.
#
# HONEST LEVEL: this is the accepted-config-SHAPE flip — the strongest RUNNABLE
# form. It is NOT a literal dynamic schema where the lens key set is itself a
# function of a settled value; that is blocked in dzm for the SAME reason as
# nixpkgs (the option set must be known to build the cycle that settles the value
# the option set would depend on). nixpkgs cannot do EVEN the shape flip via
# declaration: `imports = lib.optionals config.enable [...]` throws "infinite
# recursion encountered" (verified live), and nixpkgs' own advice is to declare
# unconditionally + gate with mkIf — which is precisely this seam, but dzm gives a
# typed LOCATED error instead of silent value-gating.
#
# OBJECTIVE ORACLE per test:
#   - enable=true  + fields present  → right (behaviour A valid/active).
#   - enable=false + fields absent   → right (behaviour B valid).
#   - enable=false + a field present → LOCATED left (the option doesn't exist here).
#   - enable=true  + fields absent   → LOCATED left (behaviour A requires them).
#   - NEGATIVE CONTROL: a check that IGNORES enable accepts a case the dependent
#     one rejects — the mutant breaks.
#   - DEPENDENCE: flip enable, the SAME config's acceptance flips.
let
  inherit (zen) fx;
  H = fx.types.hoas;

  # The Σ family: `snd enable` is the fx TYPE of the {turbo,maxSpeed} bundle for
  # the behaviour `enable` selects — LARGE ELIMINATION on the Bool value.
  behaviourShape =
    enable:
    fx.types.mkType {
      name = if enable then "Behaviour-A{turbo,maxSpeed}" else "Behaviour-B{}";
      kernelType = H.any;
      guard =
        bundle:
        if enable then
          bundle.turbo != null && bundle.maxSpeed != null
        else
          bundle.turbo == null && bundle.maxSpeed == null;
    };

  # A check that IGNORES enable: it only asks "are the fields present?" — the
  # mutant the negative control targets. A behaviour-blind acceptance.
  blindShape =
    _enable:
    fx.types.mkType {
      name = "Blind{turbo,maxSpeed present}";
      kernelType = H.any;
      guard = bundle: bundle.turbo != null && bundle.maxSpeed != null;
    };

  mkRun =
    snd: defs:
    zen.run {
      lens = {
        enable = zen.types.bool;
        turbo = zen.withDefault null zen.types.bool;
        maxSpeed = zen.withDefault null zen.types.int;
      };
      inherit defs;
      check = zen.depshape {
        index = "enable";
        fields = [
          "turbo"
          "maxSpeed"
        ];
        fst = fx.types.Bool;
        inherit snd;
      };
    };

  run = mkRun behaviourShape;
  runBlind = mkRun blindShape;

  defOn = zen.def {
    enable = true;
    turbo = true;
    maxSpeed = 200;
  };
  defOnBare = zen.def { enable = true; };
  defOffBare = zen.def { enable = false; };
  defOffTurbo = zen.def {
    enable = false;
    turbo = true;
    maxSpeed = 200;
  };
in
{
  r9 = {

    # === enable=true → BEHAVIOUR A valid/active (the fields ARE the interface) ==
    test_R9_enable_true_present_settles_right = {
      expr = run [ defOn ];
      expected = zen.bend.right {
        enable = true;
        turbo = true;
        maxSpeed = 200;
      };
    };

    # === enable=false → BEHAVIOUR B valid (the fields are absent) =============
    test_R9_enable_false_absent_settles_right = {
      expr = run [ defOffBare ];
      expected = zen.bend.right {
        enable = false;
        turbo = null;
        maxSpeed = null;
      };
    };

    # === enable=false + field PRESENT → LOCATED left (option doesn't exist) ===
    test_R9_enable_false_present_settles_located_left = {
      expr =
        let
          r = run [ defOffTurbo ];
        in
        {
          isLeft = r ? left;
          why = r.left.why or null;
          index = r.left.index or null;
          indexValue = r.left.indexValue or null;
          path = r.left.path or null;
          expected = r.left.expected or null;
        };
      expected = {
        isLeft = true;
        why = "behaviour-shape";
        index = "enable";
        indexValue = false;
        path = [
          "turbo"
          "maxSpeed"
        ];
        expected = "Behaviour-B{}";
      };
    };

    # === enable=true + fields ABSENT → LOCATED left (behaviour A requires) ====
    test_R9_enable_true_absent_settles_located_left = {
      expr =
        let
          r = run [ defOnBare ];
        in
        {
          isLeft = r ? left;
          why = r.left.why or null;
          indexValue = r.left.indexValue or null;
          expected = r.left.expected or null;
        };
      expected = {
        isLeft = true;
        why = "behaviour-shape";
        indexValue = true;
        expected = "Behaviour-A{turbo,maxSpeed}";
      };
    };

    # === DEPENDENCE — the accepted SHAPE depends on enable's VALUE (`become`) ==
    # The SAME field-present config is ACCEPTED at enable=true, REJECTED at
    # enable=false. The SAME bare config is ACCEPTED at enable=false, REJECTED at
    # enable=true. If existence were value-independent, the pairs would agree;
    # they do not — the accepted option world is `snd enable`.
    test_R9_shape_depends_on_value = {
      expr = {
        present_at_true_ok = (run [ defOn ]) ? right;
        present_at_false_rejected = (run [ defOffTurbo ]) ? left;
        bare_at_false_ok = (run [ defOffBare ]) ? right;
        bare_at_true_rejected = (run [ defOnBare ]) ? left;
      };
      expected = {
        present_at_true_ok = true;
        present_at_false_rejected = true;
        bare_at_false_ok = true;
        bare_at_true_rejected = true;
      };
    };

    # === NEGATIVE CONTROL — a mutant that IGNORES enable MUST diverge =========
    # The behaviour-blind check (`blindShape`, ignores enable, only wants the
    # fields present) ACCEPTS enable=false+present — exactly the case the
    # value-dependent check REJECTS. Pin BOTH so the test breaks if either the
    # real check stops depending on enable OR the mutant starts: the dependent
    # check rejects (left), the blind check accepts (right). A re-implementation
    # that ignored enable would make `dependent_rejects` false.
    test_R9_negative_control_blind_diverges = {
      expr = {
        dependent_rejects = (run [ defOffTurbo ]) ? left;
        blind_accepts = (runBlind [ defOffTurbo ]) ? right;
      };
      expected = {
        dependent_rejects = true;
        blind_accepts = true;
      };
    };

    # === fx Σ value-dependence at the fx layer (unit-level, no zen) ==========
    # Pins the load-bearing fact directly on fx: `fx.types.check (Sigma …)` over
    # a pair whose snd's TYPE is `snd fst` (the Bool index). Guards the fx→dzm
    # boundary against a regression masking a broken large elimination.
    test_R9_fx_sigma_large_elimination = {
      expr =
        let
          Sig = fx.types.Sigma {
            fst = fx.types.Bool;
            snd = behaviourShape;
            universe = 0;
          };
          chk =
            b: t: m:
            fx.types.check Sig {
              fst = b;
              snd = {
                turbo = t;
                maxSpeed = m;
              };
            };
        in
        {
          on_present = chk true true 200;
          on_absent = chk true null null;
          off_absent = chk false null null;
          off_present = chk false true 200;
        };
      expected = {
        on_present = true;
        on_absent = false;
        off_absent = true;
        off_present = false;
      };
    };

  };
}
