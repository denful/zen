zen:
# R7 — submodules (child cycle) + settle-fuel. The recursion + termination
# guarantees (spec §4 submodule = child cycle; §5 settle-fuel: generation bound
# K → located left{cycle}; static option identity).
#
#   - SUBMODULE = CHILD CYCLE: a submodule option resolves via a nested cycle over
#     the child module's OWN option set. The child's `config` projections run and
#     read PLAIN settled values (the zen-old Either-asymmetry is DELETED — inner
#     reads are never raw Either). A sibling that reads the submodule reads a PLAIN
#     nested config attrset.
#
#   - SETTLE-FUEL: the cycle carries a generation bound `K` (numeric, kernel.nix
#     `fuelK = 1000`). A config that converges within K rounds settles normally; a
#     genuine cyclic option reference (`a` deps `b` deps `a`) that cannot converge
#     resolves to `left { why = "cycle"; cycle = [...]; }` — LOCATED, never a Nix
#     "infinite recursion" throw and never a hang. K ≥ any legitimate
#     dependency-chain depth, so deep ACYCLIC chains still settle (pinned from
#     below by `test_R7_deep_chain`).
let
  # A depth-20 ACYCLIC dependency chain: x0 = 1; x_i = { x_{i-1} }: x_{i-1} + 1.
  # Each link is a LITERAL destructured lambda — `builtins.functionArgs` (the
  # edge-local dep inference) reads only real lambda patterns, so the chain is
  # spelled out (it also doubles as copy-paste user documentation, spec §11).
  # x20 must settle to x0 + 20 = 21. This pins K FROM BELOW (G4): the fuel must
  # NOT false-positive a 20-deep legitimate convergence as a cycle.
  deepChainModules = [
    {
      options.x0 = zen.types.int;
      config.x0 = 1;
    }
    {
      options.x1 = zen.types.int;
      config.x1 = { x0 }: x0 + 1;
    }
    {
      options.x2 = zen.types.int;
      config.x2 = { x1 }: x1 + 1;
    }
    {
      options.x3 = zen.types.int;
      config.x3 = { x2 }: x2 + 1;
    }
    {
      options.x4 = zen.types.int;
      config.x4 = { x3 }: x3 + 1;
    }
    {
      options.x5 = zen.types.int;
      config.x5 = { x4 }: x4 + 1;
    }
    {
      options.x6 = zen.types.int;
      config.x6 = { x5 }: x5 + 1;
    }
    {
      options.x7 = zen.types.int;
      config.x7 = { x6 }: x6 + 1;
    }
    {
      options.x8 = zen.types.int;
      config.x8 = { x7 }: x7 + 1;
    }
    {
      options.x9 = zen.types.int;
      config.x9 = { x8 }: x8 + 1;
    }
    {
      options.x10 = zen.types.int;
      config.x10 = { x9 }: x9 + 1;
    }
    {
      options.x11 = zen.types.int;
      config.x11 = { x10 }: x10 + 1;
    }
    {
      options.x12 = zen.types.int;
      config.x12 = { x11 }: x11 + 1;
    }
    {
      options.x13 = zen.types.int;
      config.x13 = { x12 }: x12 + 1;
    }
    {
      options.x14 = zen.types.int;
      config.x14 = { x13 }: x13 + 1;
    }
    {
      options.x15 = zen.types.int;
      config.x15 = { x14 }: x14 + 1;
    }
    {
      options.x16 = zen.types.int;
      config.x16 = { x15 }: x15 + 1;
    }
    {
      options.x17 = zen.types.int;
      config.x17 = { x16 }: x16 + 1;
    }
    {
      options.x18 = zen.types.int;
      config.x18 = { x17 }: x17 + 1;
    }
    {
      options.x19 = zen.types.int;
      config.x19 = { x18 }: x18 + 1;
    }
    {
      options.x20 = zen.types.int;
      config.x20 = { x19 }: x19 + 1;
    }
  ];

  deepChainResult = zen.run { modules = deepChainModules; };

  # The mutual cycle: config.a = { b }: b and config.b = { a }: a. Unresolvable —
  # the lazy fixpoint would THROW "infinite recursion"; settle-fuel detects the
  # back-edge in the STATIC dep graph and emits a LOCATED left{why="cycle"} instead.
  cyclicResult = zen.run {
    modules = [
      {
        options.a = zen.types.int;
        options.b = zen.types.int;
        config.a = { b }: b;
        config.b = { a }: a;
      }
    ];
  };
in
{
  r7 = {

    # === test_R7_submodule — spec §4 (OBJECTIVE ORACLE) ======================
    # A submodule option `srv` is a CHILD CYCLE: the child module declares its own
    # options (`base`, `derived`) and `config.derived = { base }: base + 100`
    # DERIVES one child option from another, reading `base` as a PLAIN settled
    # value (NOT a raw Either — the asymmetry is gone). A SIBLING (`report`) reads
    # the resolved submodule and pulls `srv.derived` as a PLAIN nested value.
    #   child base=5 ⇒ derived=105 ⇒ srv={base=5;derived=105}; report=105.
    # Proves: submodule = child cycle; inner reads plain; sibling reads plain.
    test_R7_submodule = {
      expr = zen.run {
        modules = [
          {
            options.srv = zen.types.sub;
            options.report = zen.types.int;
          }
          # The child cycle contributed to `srv`. The child's own config derives
          # `derived` from `base` (inner edge-local read, PLAIN value).
          (zen.sub {
            srv = [
              {
                options.base = zen.types.int;
                options.derived = zen.types.int;
                config.base = 5;
                config.derived = { base }: base + 100;
              }
            ];
          })
          # A sibling reads the settled submodule as a PLAIN attrset.
          { config.report = { srv }: srv.derived; }
        ];
      };
      expected = {
        right = {
          srv = {
            base = 5;
            derived = 105;
          };
          report = 105;
        };
      };
    };

    # === test_R7_deep_chain — G4 (pins K FROM BELOW) =========================
    # A depth-20 ACYCLIC chain (x0=1; x_i = x_{i-1}+1) MUST settle to the correct
    # RIGHT — x20 == x0 + 20 == 21 — NOT a false left{cycle}. Proves settle-fuel's
    # bound K is NOT over-eager: a slow-but-legitimate deep convergence is
    # distinguished from a real cycle (the paired negative control below is a real
    # cycle). If K were pinned below 20 this would wrongly become a left.
    test_R7_deep_chain = {
      expr = {
        isRight = deepChainResult ? right;
        x20 = deepChainResult.right.x20 or null;
        x0 = deepChainResult.right.x0 or null;
        x10 = deepChainResult.right.x10 or null;
      };
      expected = {
        isRight = true;
        x20 = 21;
        x0 = 1;
        x10 = 11;
      };
    };

    # === test_R7_listOf_submod_positive — composite-field-submod (listOf) =======
    # A field `deps = listOf (submod { name = str; version = str; })` receives a
    # valid list element. The `.inner` path on the submod type is exercised by
    # listOf's element lens (`bend.each (t.inner or t)` — api.nix:197). Without
    # the `.inner` fix the lens falls through to the full `opt`-wrapped type and
    # crashes at api.nix:66 (`attribute 'prio' missing`). This test is the
    # positive oracle: valid data MUST settle to `right` with the value preserved.
    test_R7_listOf_submod_positive = {
      expr = zen.run [
        {
          options.deps = zen.types.listOf (zen.types.submod {
            name = zen.types.str;
            version = zen.types.str;
          });
          config.deps = [
            {
              name = "d1";
              version = "1.0";
            }
          ];
        }
      ];
      expected = {
        right = {
          deps = [
            {
              name = "d1";
              version = "1.0";
            }
          ];
        };
      };
    };

    # === test_R7_listOf_submod_neg_wrong_type — negative control A (listOf) ====
    # Same field; element has `version = 123` (int, not str). The nested element
    # lens (`submodOf`) MUST reject it: result is `left` with `deps` failing.
    # Proves the element lens actually fires and validates nested field types,
    # not a passthrough. If `.inner` were absent the crash at :66 would mask the
    # type error — this test proves real validation, not a no-op passthrough.
    test_R7_listOf_submod_neg_wrong_type =
      let
        r = zen.run [
          {
            options.deps = zen.types.listOf (zen.types.submod {
              name = zen.types.str;
              version = zen.types.str;
            });
            config.deps = [
              {
                name = "d1";
                version = 123;
              }
            ];
          }
        ];
      in
      {
        expr = zen.test.fieldError r "deps";
        expected = true;
      };

    # === test_R7_listOf_submod_neg_missing_field — negative control B (listOf) ==
    # Element omits the required `version` field entirely. The submod lens calls
    # `bend.recordAll` which rejects missing required fields. Result is `left`
    # with `deps` failing. Paired with neg_wrong_type this proves the full
    # submod validator (field-presence AND type) fires through the listOf path.
    test_R7_listOf_submod_neg_missing_field =
      let
        r = zen.run [
          {
            options.deps = zen.types.listOf (zen.types.submod {
              name = zen.types.str;
              version = zen.types.str;
            });
            config.deps = [
              {
                name = "d1";
              }
            ];
          }
        ];
      in
      {
        expr = zen.test.fieldError r "deps";
        expected = true;
      };

    # === test_R7_attrsOf_submod_positive — composite-field-submod (attrsOf) ====
    # A field `deps = attrsOf (submod { name = str; version = str; })` receives a
    # valid attrset of elements. Exercises `bend.eachValue (t.inner or t)` path
    # (api.nix:203) — the attrsOf parallel of the listOf fix. Valid data MUST
    # settle to `right` with the value preserved, proving the `.inner` path on
    # attrsOf also correctly resolves the nested submod lens.
    test_R7_attrsOf_submod_positive = {
      expr = zen.run [
        {
          options.deps = zen.types.attrsOf (zen.types.submod {
            name = zen.types.str;
            version = zen.types.str;
          });
          config.deps = {
            d1 = {
              name = "d1";
              version = "1.0";
            };
          };
        }
      ];
      expected = {
        right = {
          deps = {
            d1 = {
              name = "d1";
              version = "1.0";
            };
          };
        };
      };
    };

    # === NEGATIVE CONTROL: test_R7_cyclic_reference — spec §5/§10 =============
    # A mutual option reference (config.a = { b }: b; config.b = { a }: a) is an
    # unresolvable cycle. zen-old / a naive actor cycle would HANG; Nix's lazy
    # fixpoint would THROW "infinite recursion encountered" (unlocated,
    # uncatchable). Settle-fuel detects the static-graph back-edge and converts it
    # to a LOCATED `left { why = "cycle"; cycle = [...]; path = "a"; }`. No throw,
    # no hang — the spec's central no-throw-on-cycles guarantee.
    #   ⇒ left; why = "cycle"; cycle members = { "a", "b" } located at "a".
    # (Wall-clock < 1s is proven at the oracle by running the suite under
    #  `timeout` — a hang would blow the timeout; this asserts the SHAPE.)
    test_R7_cyclic_reference = {
      expr = {
        isLeft = cyclicResult ? left;
        why = cyclicResult.left.a.left.why or null;
        # The located cycle path for option `a` (its first-occurrence suffix).
        cycle = cyclicResult.left.a.left.cycle or null;
        path = cyclicResult.left.a.left.path or null;
        # `b` is ALSO located as a cycle member (every node on the cycle is blamed).
        bWhy = cyclicResult.left.b.left.why or null;
      };
      expected = {
        isLeft = true;
        why = "cycle";
        cycle = [
          "a"
          "b"
        ];
        path = "a";
        bWhy = "cycle";
      };
    };
  };
}
