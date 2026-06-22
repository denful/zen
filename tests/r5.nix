zen:
# R5 — stateful reconcile (deterministic fold) + delegation (typed capabilities).
#
# The first-class-actor payoff: power dnzl has and zen-old lacks, surfaced as
# TYPED combinators over the declarative module surface.
#
#   - zen.reconcile init step coll : a stateful fold whose engine is the dnzl
#     actor (`ned.st.scanl` = actor + become), but over a DETERMINISTIC list, so
#     the output is a pure function of the input SET (spec §4.2). Usable inside a
#     `config.<opt> = {deps}: zen.reconcile ...` contribution.
#   - delegation A : a capability that is a function value (`zen.t.fn`), passed
#     through the typed dep graph and APPLIED by a consumer (spec §4.3 Flavor A).
#   - delegation B : a capability that is a dnzl actor-handle (`zen.t.actor`),
#     queried via `zen.send` — a fresh point-to-point session (spec §4.3 Fl. B).
#
# (Function-valued options are projected out of each `expr` before comparison:
#  a Nix lambda has no stable equality, so we assert the DERIVED data instead.)
let
  inherit (builtins)
    sort
    lessThan
    attrNames
    listToAttrs
    map
    removeAttrs
    ;

  # The §4.2 step: each service claims `portCount` ports starting at `acc.next`;
  # `out.<name>` records the BASE assigned to that service. Order-sensitive (each
  # base depends on the running `next`), so determinism is structural, not luck.
  allocStep = services: acc: name: {
    next = acc.next + services.${name}.portCount;
    out = acc.out // {
      ${name} = acc.next;
    };
  };

  # The §4.2 port-allocator contribution: fold over the SORTED service names.
  allocBases =
    services:
    (zen.reconcile {
      next = 8000;
      out = { };
    } (allocStep services) (sort lessThan (attrNames services))).out;

  services = {
    web = {
      portCount = 2;
    };
    db = {
      portCount = 1;
    };
    cache = {
      portCount = 3;
    };
  };
  # Bases over sorted [cache db web]: cache@8000(+3) db@8003(+1) web@8004(+2).
  expectedBases = {
    cache = 8000;
    db = 8003;
    web = 8004;
  };

  # The delegation-B running-total actor: reply.right the new total, become the
  # next state. A genuine dnzl actor-handle (stateful via `become`).
  counterActor = zen.actor (
    let
      go = total: amt: (zen.reply.right (total + amt)) // (zen.become (go (total + amt)));
    in
    go 0
  );

in
{
  r5 = {

    # === test_R5_port_allocator — spec §4.2 stateful reconcile ================
    # A derived contribution allocates non-overlapping port ranges via a fold
    # over the deterministic (sorted) service-name list. The base each service
    # gets is the running `next` BEFORE its own `portCount` is consumed.
    test_R5_port_allocator = {
      expr = zen.run {
        modules = [
          {
            options.services = zen.opt zen.m.unique zen.t.any;
            options.portBase = zen.opt zen.m.unique zen.t.any;
            config.services = services;
            config.portBase = { services }: allocBases services;
          }
        ];
      };
      expected = {
        right = {
          inherit services;
          portBase = expectedBases;
        };
      };
    };

    # === test_R5_determinism (G3 — order-invariance) =========================
    # The fold is ORDER-SENSITIVE (each base depends on the running total), yet
    # the §4.2 contract SORTS the input before folding, so the result is a pure
    # function of the input SET — identical whether the raw names arrive in
    # forward or REVERSED order, because both are sorted to the same list before
    # the fold. The adversarial mutation (drop the `sort`, fold in raw order)
    # makes the forward and reversed inputs diverge, failing this assertion.
    test_R5_determinism =
      let
        rawNames = attrNames services;
        reversed = sort (a: b: lessThan b a) rawNames; # a different arrival order
        # Both paths sort ascending inside, then fold — the §4.2 discipline.
        foldSorted =
          names:
          (zen.reconcile {
            next = 8000;
            out = { };
          } (allocStep services) (sort lessThan names)).out;
      in
      {
        expr = foldSorted rawNames == foldSorted reversed && foldSorted rawNames == expectedBases;
        expected = true;
      };

    # === test_R5_delegation_A — function capability (spec §4.3 Flavor A) ======
    # A vendor module exposes `mkHome` as a FUNCTION value (zen.t.fn). A consumer
    # reads it as a named dep and APPLIES it — no `send`, no stringly ref; the
    # capability flowed through the typed dep graph as an ordinary option value.
    # We project out the fn-valued `mkHome` before comparison (lambdas have no
    # stable equality); the DERIVED `homes` proves the capability was applied.
    test_R5_delegation_A = {
      expr =
        let
          r = zen.run {
            modules = [
              {
                options.baseDir = zen.opt zen.m.unique zen.t.str;
                options.mkHome = zen.opt zen.m.unique zen.t.fn;
                options.userList = zen.t.listOf zen.t.str;
                options.homes = zen.t.attrsOf zen.t.str;
                config.baseDir = "/home";
                config.userList = [
                  "ada"
                  "linus"
                ];
                config.mkHome = { baseDir }: (user: "${baseDir}/${user}");
                config.homes =
                  { mkHome, userList }:
                  listToAttrs (
                    map (u: {
                      name = u;
                      value = mkHome u;
                    }) userList
                  );
              }
            ];
          };
        in
        {
          right = removeAttrs r.right [ "mkHome" ];
        };
      expected = {
        right = {
          baseDir = "/home";
          userList = [
            "ada"
            "linus"
          ];
          homes = {
            ada = "/home/ada";
            linus = "/home/linus";
          };
        };
      };
    };

    # === test_R5_delegation_B — actor-handle + zen.send (spec §4.3 Flavor B) ===
    # `counter` is a dnzl actor-handle capability (zen.t.actor): a stateful
    # running-total actor. A consumer queries it with `zen.send counter batch` —
    # a fresh point-to-point session — yielding the per-message totals. The
    # fn-valued `counter` is projected out before comparison.
    #
    # The actor-handle is supplied as a no-dep projection `{ }: <actor>` — the
    # same projection surface a function capability uses (Flavor A is a
    # `{deps}: <fn>`), which both disambiguates a capability VALUE from a derived
    # projection AND lets the engine box the fn result as opaque cycle data.
    #   send 10,20,30 ⇒ totals 10,30,60.
    test_R5_delegation_B = {
      expr =
        let
          r = zen.run {
            modules = [
              {
                options.counter = zen.opt zen.m.unique zen.t.actor;
                options.batch = zen.t.listOf zen.t.int;
                options.totals = zen.t.listOf zen.t.int;
                config.counter = { }: counterActor;
                config.batch = [
                  10
                  20
                  30
                ];
                config.totals = { counter, batch }: zen.send counter batch;
              }
            ];
          };
        in
        {
          right = removeAttrs r.right [ "counter" ];
        };
      expected = {
        right = {
          batch = [
            10
            20
            30
          ];
          totals = [
            10
            30
            60
          ];
        };
      };
    };

    # === test_R5_nondeterminism_guard — NEGATIVE control (TEST#2) =============
    # SURFACE-constructible: a user passes `reconcile` a NON-LIST collection (an
    # unordered attrset) — no deterministic iteration order — so the fold is
    # REJECTED at the API boundary with a located left. Distinct from a plain
    # type-rejection: the positive determinism test pins order-invariance on an
    # order-SENSITIVE step, so this guard is the only thing between a list and a
    # nondeterministic fold.
    test_R5_nondeterminism_guard = {
      expr =
        (zen.reconcile { next = 8000; } (acc: _: acc) {
          web = 1;
          db = 2;
        }).left.why;
      expected = "non-deterministic-fold";
    };
  };
}
