zen:
# R6 — negotiated merge + scoped DI. The first-class-effects payoff:
#
#   - zen.m.conflict : a merge strategy that, when MORE THAN ONE same-priority
#     survivor reaches it, does NOT pick blindly — it SIGNALS a condition
#     (`fx.effects.conditions.signal "conflict"`) carrying the survivor `defs`
#     and the allowed restarts `[ use-first use-last reject ]`. A `condition`
#     handler installed at the WORLD EDGE (via `zen.run { handlers = {...}; }`,
#     threaded into the kernel's `ned.ctx-d` handler stack) picks the resolution.
#     The resolvers are surfaced as `zen.resolve.{useFirst,useLast,reject}`.
#
#     CRUCIAL ordering: the conflict signal fires AFTER R3's priority pre-filter,
#     so it sees ONLY genuine same-priority survivors — a `mkForce` (prio 50)
#     racing a bare def (prio 100) leaves ONE survivor, so NO signal fires and
#     the value resolves directly even with a `reject` handler armed (pinned by
#     `test_R6_conflict_respects_priority_filter`).
#
#   - scoped DI : `zen.provide` / `zen.request` are thin sugar over `ned.ctx-d`
#     (the lexically-scoped handler stack). `send` does NOT replace this — a
#     nested `provide` SHADOWS an outer one, nearest-enclosing provider winning
#     (lexical), which a fresh scope-free `send` session could not express.
#
# (Resolution handlers and provider closures are Nix lambdas with no stable
#  equality; every assertion compares the DERIVED settled config, never a fn.)
let
  inherit (zen) ned;

  # A requester contribution for option `name` that reads the injected dep `X`
  # and records it as `name`'s value. `zen.request` wraps it in `ned.st` so the
  # nearest-enclosing `zen.provide` resolves `X`.
  reqX =
    name:
    zen.request {
      ${name} = (
        { X }: {
          value = X;
          file = "<di>";
          prio = 100;
        }
      );
    };

in
{
  r6 = {

    # === test_R6_negotiated_merge — spec §8 (OBJECTIVE ORACLE) ================
    # Two BARE (same-priority, prio 100) conflicting defs into a `conflict`
    # option. Both survive R3's priority filter (same class) ⇒ the strategy
    # signals "conflict" ⇒ the installed `use-last` handler RESOLVES it to the
    # order-last survivor. Result is a settled RIGHT (resolved, not left).
    #   defs [1, 2] + useLast ⇒ right { x = 2 }.
    test_R6_negotiated_merge = {
      expr = zen.run {
        modules = [
          {
            options.x = zen.opt zen.m.conflict zen.t.int;
            config.x = 1;
          }
          { config.x = 2; }
        ];
        handlers = {
          condition = zen.resolve.useLast;
        };
      };
      expected = {
        right = {
          x = 2;
        };
      };
    };

    # === test_R6_conflict_respects_priority_filter (G — R3 ordering) ==========
    # The negotiated merge runs STRICTLY AFTER R3's priority pre-filter. A
    # `mkForce` (prio 50) racing a bare def (prio 100) is NOT a conflict: the
    # filter drops the bare, leaving ONE survivor, so NO signal fires — the value
    # resolves directly to the force EVEN THOUGH a `reject` handler is armed. If
    # conflict fired on the pre-filter inputs (wrong order) the reject would win
    # and this would be a left. Proves "conflict sees only same-priority
    # survivors".
    test_R6_conflict_respects_priority_filter = {
      expr = zen.run {
        modules = [
          {
            options.x = zen.opt zen.m.conflict zen.t.int;
            config.x = zen.mkForce 99;
          }
          { config.x = 7; }
        ];
        # Armed to REJECT — but it must never fire (single survivor, no signal).
        handlers = {
          condition = zen.resolve.reject;
        };
      };
      expected = {
        right = {
          x = 99;
        };
      };
    };

    # === test_R6_di_shadowing — spec §9 (OBJECTIVE ORACLE) ====================
    # Nested `provide` lexical shadowing. An OUTER `provide X=1` wraps an INNER
    # `provide X=2`; a requester UNDER the inner scope resolves to the NEAREST
    # enclosing provider (2), while a sibling requester under ONLY the outer
    # scope resolves to 1. This is the ctx-d handler stack — `send` (a fresh
    # scope-free session) could not express the nesting.
    #   inner ⇒ 2 (nearest-enclosing wins), outer ⇒ 1 (lexical shadowing).
    test_R6_di_shadowing = {
      expr = zen.run [
        {
          options.inner = zen.types.int;
          options.outer = zen.types.int;
        }
        # Outer provider X=1 over BOTH the inner-provide block and the bare
        # outer requester. The inner block re-provides X=2 around its requester.
        (zen.provide { X = 1; } (
          srcs:
          let
            innerBlock = zen.provide { X = 2; } (reqX "inner");
            outerReq = reqX "outer";
          in
          (innerBlock srcs) // (outerReq srcs)
        ))
      ];
      expected = {
        right = {
          inner = 2; # nearest-enclosing provider (inner X=2) wins
          outer = 1; # outer-only scope sees the outer provider (X=1)
        };
      };
    };

    # === NEGATIVE CONTROL: test_R6_conflict_reject ===========================
    # Same two same-priority conflicting defs, but the installed handler chooses
    # the `reject` restart. The negotiation REFUSES — the `reject` branch is real
    # (not decorative): the option settles to a LOCATED `left { why = "conflict";
    # defs = [...]; path = "x"; ... }`, NOT a throw. Proves the handler can
    # decline and the refusal surfaces as a normal Either-left through the
    # accumulating aggregate.
    test_R6_conflict_reject =
      let
        r = zen.run {
          modules = [
            {
              options.x = zen.opt zen.m.conflict zen.t.int;
              config.x = 1;
            }
            { config.x = 2; }
          ];
          handlers = {
            condition = zen.resolve.reject;
          };
        };
      in
      {
        expr = {
          isLeft = r ? left;
          why = r.left.x.left.why or null;
          # the survivor defs are carried on the rejected left (located blame).
          values = if r ? left && r.left.x.left ? defs then map (d: d.value) r.left.x.left.defs else null;
        };
        expected = {
          isLeft = true;
          why = "conflict";
          values = [
            1
            2
          ];
        };
      };
  };
}
