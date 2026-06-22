zen:
# R3 — mk* overrides + nixpkgs-grade priority/order resolution.
#
# R3 adds the override constructors (mkOverride/mkForce/mkDefault/mkOrder/
# mkBefore/mkAfter/mkIf/mkMerge) as first-class def VALUES, and the per-option
# resolution pipeline that mirrors nixpkgs `mergeDefinitions` EXACTLY:
#
#   discharge mkIf (drop when false)            [bridge]
#   → mkMerge fans out to multiple defs         [bridge]
#   → filter to the numerically-LOWEST priority class — a FILTER, not a selector:
#     EVERY def at the top priority survives, all higher-numbered are DROPPED
#   → sort survivors by the order axis           [api.nix resolveStage]
#   → apply the option's merge strategy          [merge.nix]
#   → apply the type lens                         [api.nix typed]
#
# Priorities are EXACT nixpkgs (lib/modules.nix:1589-1627):
#   mkForce=50  bare=100  mkDefault=1000  optionDefault=1500
#   mkBefore=500  mkAfter=1500  default order=1000
#
# The cheat-proof discriminator is test_R3_priority_is_filter (G1): its
# `z ∉ result` clause FAILS any impl that forgets to DROP sub-top-priority defs
# (a no-op filter would let the bare `z` through). The adversarial mutation
# proof (filter → pass-all) confirms this clause is load-bearing.
let
  inherit (zen) bend;
  inherit (builtins) elem;
in
{
  r3 = {

    # === test_R3_overrides — the mk* family in one module ===================
    # Five independent options, each exercising one override axis:
    #   force    : mkForce 80 vs bare 100        ⇒ 80    (prio 50 wins the filter)
    #   deflt    : mkDefault "info" vs bare      ⇒ bare  (prio 1000 loses to 100)
    #   gated    : mkIf false {...}              ⇒ absent (discharged → no def;
    #                                               supplies a fallback so the
    #                                               option still settles)
    #   fanned   : mkMerge [["a"]["b"]] (concat) ⇒ ["a" "b"] (one module, 2 defs)
    #   ordered  : mkBefore/bare/mkAfter (concat)⇒ ["e" "m" "l"] (order axis sorts)
    test_R3_overrides = {
      expr = zen.run {
        modules = [
          {
            options.force = zen.opt zen.m.unique zen.t.int;
            options.deflt = zen.opt zen.m.unique zen.t.str;
            options.gated = zen.opt zen.m.unique zen.t.int;
            options.fanned = zen.opt zen.m.concat (bend.each bend.str);
            options.ordered = zen.opt zen.m.concat (bend.each bend.str);

            # mkForce (50) BEATS bare (100): priority filter keeps only the force.
            config.force = zen.mkForce 80;
            # mkDefault (1000) LOSES to bare (100): the bare def survives the filter.
            config.deflt = zen.mkDefault "fallback";
            # mkIf false ⇒ this def is dropped; a bare fallback keeps `gated` settled.
            config.gated = zen.mkMerge [
              (zen.mkIf false 999)
              7
            ];
            # mkMerge fans ONE module's config into TWO concat defs.
            config.fanned = zen.mkMerge [
              [ "a" ]
              [ "b" ]
            ];
            # order axis: mkBefore (500) < bare (1000) < mkAfter (1500).
            config.ordered = zen.mkMerge [
              (zen.mkAfter [ "l" ])
              [ "m" ]
              (zen.mkBefore [ "e" ])
            ];
          }
          {
            # A second module supplies the bare defs that force/default race against.
            config.force = 100;
            config.deflt = "bare-wins";
          }
        ];
      };
      expected = {
        right = {
          force = 80;
          deflt = "bare-wins";
          gated = 7;
          fanned = [
            "a"
            "b"
          ];
          ordered = [
            "e"
            "m"
            "l"
          ];
        };
      };
    };

    # === test_R3_priority_is_filter (G1 — THE critical discriminator) =======
    # concat-strategy option with [ mkForce [x]; bare [z]; mkForce [y] ].
    #   * priority is a FILTER: the two mkForce (50) survive, the bare [z] (100)
    #     is DROPPED. Both forces then concat in order ⇒ result == [ "x" "y" ].
    #   * The `z ∉ result` clause is LOAD-BEARING: a no-op filter (pass all
    #     survivors) would concat [x],[z],[y] ⇒ [ "x" "z" "y" ], so `z ∈ result`
    #     and this test FAILS. (Proven real by the adversarial mutation: stubbing
    #     resolveDefs to pass all defs makes `zPresent = true` here.)
    test_R3_priority_is_filter =
      let
        r = zen.run {
          modules = [
            {
              options.xs = zen.opt zen.m.concat (bend.each bend.str);
              config.xs = zen.mkMerge [
                (zen.mkForce [ "x" ])
                [ "z" ]
                (zen.mkForce [ "y" ])
              ];
            }
          ];
        };
        xs = r.right.xs or null;
      in
      {
        expr = {
          isRight = r ? right;
          result = xs;
          zPresent = if xs == null then null else elem "z" xs;
        };
        expected = {
          isRight = true;
          result = [
            "x"
            "y"
          ];
          zPresent = false; # z is DROPPED by the priority filter.
        };
      };

    # === test_R3_mkOverride (explicit n) ===================================
    # mkOverride 50 ≡ mkForce semantics (beats bare 100); mkOverride 1000 ≡
    # mkDefault semantics (loses to bare 100). Pins the GENERAL constructor the
    # named aliases specialize.
    test_R3_mkOverride = {
      expr = zen.run {
        modules = [
          {
            options.a = zen.opt zen.m.unique zen.t.int;
            options.b = zen.opt zen.m.unique zen.t.int;
            config.a = zen.mkOverride 50 1; # 50 < 100 ⇒ wins
            config.b = zen.mkOverride 1000 1; # 1000 > 100 ⇒ loses
          }
          {
            config.a = 2; # bare 100
            config.b = 2; # bare 100
          }
        ];
      };
      expected = {
        right = {
          a = 1; # mkOverride 50 beat bare
          b = 2; # mkOverride 1000 lost to bare
        };
      };
    };

    # === test_R3_mkOrder (explicit n) ======================================
    # mkOrder n sets the order axis; all same priority (100), so all survive the
    # filter and the concat is sequenced by n: 250 < 1000(bare) < 1750.
    test_R3_mkOrder = {
      expr = zen.run {
        modules = [
          {
            options.xs = zen.opt zen.m.concat (bend.each bend.str);
            config.xs = zen.mkMerge [
              (zen.mkOrder 1750 [ "late" ])
              [ "mid" ]
              (zen.mkOrder 250 [ "early" ])
            ];
          }
        ];
      };
      expected = {
        right = {
          xs = [
            "early"
            "mid"
            "late"
          ];
        };
      };
    };

    # === NEGATIVE CONTROL: test_R3_unique_conflict =========================
    # Two BARE defs (both prio 100) into a `unique` option ⇒ both survive the
    # filter (same priority class) ⇒ unique sees 2 defs ⇒ left{ why = "conflict" }.
    # Proves the filter is NOT a selector: it does not silently collapse a genuine
    # same-priority conflict, and `unique` correctly rejects it.
    test_R3_unique_conflict =
      let
        r = zen.run {
          modules = [
            {
              options.x = zen.opt zen.m.unique zen.t.int;
              config.x = 1;
            }
            { config.x = 2; }
          ];
        };
      in
      {
        expr = {
          isLeft = r ? left;
          why = r.left.x.left.why or null;
        };
        expected = {
          isLeft = true;
          why = "conflict";
        };
      };

  };
}
