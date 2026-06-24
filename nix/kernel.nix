zen:
let
  inherit (zen) ned;
  anyLeft = as: builtins.any (v: v ? left) (builtins.attrValues as);
  eachRight = builtins.mapAttrs (_: v: v.right);
  inherit (zen) bend;
  inherit (builtins)
    mapAttrs
    attrNames
    foldl'
    head
    filter
    concatMap
    length
    ;

  # === CYCLE DETECTION + TOPO ORDER (spec §5, §10) ==============================
  #
  # A genuine cyclic option reference (`config.a = { b }: b; config.b = { a }: a`)
  # is a back-edge in the STATIC dependency graph (mods.graphOf). Nix's lazy
  # fixpoint (`ned.run`) would force `sinks.a → sinks.b → sinks.a …` and THROW
  # "infinite recursion encountered" — an unlocated, uncatchable engine throw, the
  # exact failure the no-throw law forbids.
  #
  # Single Kahn topo-sort (iterative foldl', NO recursion, NO fuel cap, O(V+E)):
  #   Emitted nodes  = acyclic nodes          → `topoOrder` for deepSeq pre-force.
  #   Unemitted nodes = cycle members          → `cyclicSet` for cycle detection.
  #   One pass feeds BOTH outputs; no duplicate Kahn.
  #   No fuel, no magic constant: every bound is `length <nodes>` (data-driven).
  #
  # Cycle-path reconstruction (iterative, data-driven bound, TOTAL):
  #   From a cyclic node, follow one cyclic dependency at each step (deps that are
  #   also absent from the topo order), accumulating a path list. When a node
  #   repeats, the segment from its first occurrence is the minimal cycle. When
  #   there are no further cyclic deps (empty list), return the path so far —
  #   that IS the done-condition; `head` is never called on an empty list.
  #   Bound: `length cyclicNodes` (distinct cyclic nodes before forced to repeat).
  #   No recursion, no magic constant.
  #
  # `kahnPass graph` returns `{ topoOrder :: [node]; cyclicSet :: attrset }`.
  # Called once inside `run`; both outputs threaded from that single call.
  kahnPass =
    graph:
    let
      opts = attrNames graph;
      depsOf = n: filter (d: graph ? ${d}) (graph.${n} or [ ]);
      initInDeg = builtins.listToAttrs (
        map (n: {
          name = n;
          value = length (depsOf n);
        }) opts
      );
      initRevEdges =
        let
          pairs = concatMap (
            n:
            map (d: {
              node = n;
              dep = d;
            }) (depsOf n)
          ) opts;
          grouped = builtins.groupBy (p: p.dep) pairs;
        in
        builtins.mapAttrs (_: ps: map (p: p.node) ps) grouped;
      initQueue = filter (n: initInDeg.${n} == 0) opts;
      # One Kahn step: dequeue head, emit it, decrement successors' in-degrees.
      # queue == [] is the idle sentinel (the foldl' over-iterates for cycles).
      kahnStep =
        st: _:
        if st.queue == [ ] then
          st
        else
          let
            n = builtins.head st.queue;
            succs = st.revEdges.${n} or [ ];
            newZero = filter (s: (st.inDeg.${s} or 0) - 1 == 0) succs;
            newInDeg = foldl' (acc: s: acc // { ${s} = (acc.${s} or 0) - 1; }) st.inDeg succs;
          in
          {
            queue = builtins.tail st.queue ++ newZero;
            inDeg = newInDeg;
            inherit (st) revEdges;
            # prepend = O(1); reversed to dependency order at the end
            order = [ n ] ++ st.order;
          };
      raw = builtins.foldl' kahnStep {
        queue = initQueue;
        inDeg = initInDeg;
        revEdges = initRevEdges;
        order = [ ];
      } (builtins.genList (i: i) (length opts));
      emittedSet = foldl' (acc: n: acc // { ${n} = true; }) { } raw.order;
      # topoOrder: emitted nodes reversed from prepend-order → dependency order
      topoOrder = builtins.foldl' (acc: x: [ x ] ++ acc) [ ] raw.order;
      # cyclicSet: nodes absent from emitted order = cycle members
      cyclicSet = foldl' (acc: n: if emittedSet ? ${n} then acc else acc // { ${n} = true; }) { } opts;
    in
    {
      inherit topoOrder cyclicSet;
    };

  # cycleLeftsFrom cyclicSet depsOf opts:
  # For each cyclic node, reconstruct a minimal cycle path and wrap as
  # `left { why = "cycle"; cycle = [path]; path = n; file = "<mod>"; }`.
  # TOTAL: the path-step treats empty cyclicDeps as the done-condition —
  # no `head` is called on an empty list.
  cycleLeftsFrom =
    cyclicSet: depsOf: opts:
    let
      # cyclePathFrom: iterative, bound by length of opts (data-driven).
      cyclePathFrom =
        s:
        let
          step =
            st: _:
            if st.done then
              st
            else
              let
                cur = builtins.elemAt st.path (length st.path - 1);
                # All cyclic deps of cur — may be [] when cur's only deps are
                # acyclic (back-edge dissolved by prior steps). Empty = done.
                cyclicDeps = filter (d: cyclicSet ? ${d}) (depsOf cur);
              in
              if cyclicDeps == [ ] then
                # No further cyclic dep to follow: return path so far.
                {
                  inherit (st) path;
                  done = true;
                }
              else
                let
                  nxt = builtins.head cyclicDeps; # non-empty by guard above
                  pathLen = length st.path;
                  idxOfNxt = foldl' (
                    acc: i: if acc == null && builtins.elemAt st.path i == nxt then i else acc
                  ) null (builtins.genList (i: i) pathLen);
                in
                if idxOfNxt != null then
                  # nxt already in path: segment from idxOfNxt is the minimal cycle.
                  {
                    path = builtins.genList (i: builtins.elemAt st.path (idxOfNxt + i)) (pathLen - idxOfNxt);
                    done = true;
                  }
                else
                  {
                    path = st.path ++ [ nxt ];
                    done = false;
                  };
          result = builtins.foldl' step {
            path = [ s ];
            done = false;
          } (builtins.genList (i: i) (length opts));
        in
        result.path;
    in
    foldl' (
      a: n:
      if !(cyclicSet ? ${n}) then
        a
      else
        a
        // {
          ${n} = bend.left {
            why = "cycle";
            cycle = cyclePathFrom n;
            path = n;
            file = "<mod>";
          };
        }
    ) { } opts;

  toSt =
    v:
    if v ? toList then
      v
    else
      ned.st {
        value = v;
        file = "<def>";
        prio = 100;
      };

  applyLenses =
    lens: rawSrcs: mapAttrs (n: src: if lens ? ${n} then src (lens.${n}) else src) rawSrcs;

  # step accumulates, per option key, a NATIVE LIST of per-def contribution
  # streams in def-visitation (left-to-right foldl') order. Deferring the
  # stream concatenation to one `ned.st.fromList` (in `cycle`) keeps construction
  # O(1) stack depth per element — a left-nested fold of N functor `concat`s
  # builds a depth-N stream whose head force recurses N deep (stack overflow at
  # N >~ 4100); a flat fromList does not. Each contribution keeps its `toSt`
  # wrapping; `acc.${k} or []` preserves the empty-list default for first touch.
  step =
    srcs: acc: d:
    let
      s = d srcs;
    in
    foldl' (a: k: a // { ${k} = (a.${k} or [ ]) ++ [ (toSt s.${k}) ]; }) acc (attrNames s);

  # Default: unresolved conflict returns a negotiating left (no handler installed).
  defaultHandlers = {
    condition =
      { param, state }:
      {
        inherit state;
        resume = {
          restart = "negotiating";
          value = {
            left = {
              why = "negotiating";
              defs = param.data.defs;
            };
          };
        };
      };
    # Default `typeCheck` handler: resume with the SAME plain `left { why; got; }`
    # the `typed` lens (api.nix) returned before this became an effect — so the
    # default path (no caller `handlers.typeCheck`) is byte-identical to before.
    # `param` IS the signalled `{ why = "type"; got; }` record (raw `fx.send`,
    # not wrapped like `conditions.signal`'s `{name;data;}`), so it is read
    # directly. The continuation `(resp: fx.pure resp.value)` reads `.value`, so
    # the resumed left is carried under `value` (mirroring merge.nix `r.value`).
    typeCheck =
      { param, state }:
      {
        inherit state;
        resume = {
          value = bend.left { inherit (param) why got; };
        };
      };
  };

  # cycle folds every def into a per-key list of contribution streams (key set
  # from `mapAttrs over lens`, contributions in def order), THEN converts each
  # key's list to a single stream ONCE: `flatten (fromList contribs)` emits
  # `elems(c0) ++ elems(c1) ++ ...` — identical element sequence to the former
  # left-nested `concat`, but O(1) stack depth per element (the primitive
  # `reconcile`/`merge` rely on). A key with zero contributions yields `ned.st`
  # (the empty stream), exactly as the old `mapAttrs (_: _: ned.st) lens` seed.
  cycle =
    lens: defs: rawSrcs:
    let
      srcs = applyLenses lens rawSrcs;
      perKey = foldl' (step srcs) (mapAttrs (_: _: [ ]) lens) defs;
    in
    mapAttrs (
      _: contribs:
      if contribs == [ ] then
        ned.st
      else
        # mode E: RIGHT fold of `ned.st.concat` over the contribution streams,
        # `elems(c0) ++ elems(c1) ++ … ++ []` — identical element sequence to the
        # former `flatten (fromList contribs)`. Each `acc` is the lazy concat tail
        # (`fx.stream.concat` defers s2 in a thunk), so head-force descends only
        # one contribution at a time: O(1) Nix stack at any N (the property the
        # flatten shape gave, without flatMap's per-element rewrap). Seed `ned.st`
        # is the empty stream (concat identity), matching the `[]` branch.
        let
          n = length contribs;
          go = i: if i == n then ned.st else (builtins.elemAt contribs i).concat (go (i + 1));
        in
        go 0
    ) perKey;

  # aggregate :: { <opt> = Either; ... } -> { left | right }
  # ACCUMULATING blame (spec §10, bend.recordAll-style): if ANY option settles to a
  # `left`, fail — but collect EVERY failing option's blame, never short-circuit on
  # the first. The result `left` keeps the per-option keys (so `left.<opt>.left.why`
  # stays addressable) AND carries `errors`, the flat list of ALL failing options'
  # blame records `{ path, file, got, why, ... }`. `test_blame_accumulates` pins
  # that two independent faults both appear here (length >= 2); a first-fail impl
  # returning a single error fails it. `errors` is built by folding over EVERY
  # option key and keeping the `.left` of each that failed — every fault, in
  # declaration order.
  collectErrors =
    eithers:
    foldl' (a: k: if eithers.${k} ? left then a ++ [ eithers.${k}.left ] else a) [ ] (
      attrNames eithers
    );

  aggregate =
    eithers:
    if anyLeft eithers then
      {
        left = eithers // {
          errors = collectErrors eithers;
        };
      }
    else
      { right = eachRight eithers; };

  # unknownTargets :: validTargets -> [defProducer] -> sources -> { <opt> = <leftEither>; ... }
  # Edge-local target-key check (spec §4): every `config.<name>` target must be a
  # member of the valid target namespace = the merged option set ∪ any registered
  # driver channels (custom named channels live in `drivers`, not `lens`). A
  # contribution whose target key is declared nowhere ⇒ an `unknown-option` left.
  # `attrNames (d sources)` reads the contribution KEYS structurally — it does NOT
  # force any contribution VALUE, so this stays edge-local (no all-settled fan-in).
  unknownTargets =
    validTargets: defs: sources:
    let
      keysOf = d: filter (k: !(validTargets ? ${k})) (attrNames (d sources));
      bad = concatMap keysOf defs;
    in
    foldl' (
      a: k:
      a
      // {
        ${k} = bend.left {
          why = "unknown-option";
          got = k;
          path = k;
          file = "<mod>";
        };
      }
    ) { } bad;

  run =
    arg:
    let
      # Entry shapes: `{ modules = [...]; }` (zen surface), a bare module list
      # (legacy), or a pre-built `{ lens, defs }` params record.
      #
      # `fromMods` desugars modules into a bare `{ lens, defs }` record, so the
      # `{ modules = [...]; ... }` surface MUST carry its sibling control keys
      # (`handlers` — the negotiated-merge condition handlers, R6 — plus `check`
      # and `drivers`) THROUGH the desugar; otherwise `params.handlers` is
      # structurally absent and the world-edge `ned.ctx-d handlers` (below) only
      # ever sees `defaultHandlers`, silently dropping the caller's resolution
      # (a `conflict` survivor would always settle to `left{why="negotiating"}`).
      # The pre-built `{ lens, ... }` shape already carries every key (it IS the
      # params record); the bare-list shape has no sibling keys.
      params =
        if arg ? lens then
          arg
        else if arg ? modules then
          zen.fromMods arg.modules // builtins.removeAttrs arg [ "modules" ]
        else
          zen.fromMods arg;
      inherit (params) lens defs;
      check = params.check or null;
      drivers = mapAttrs (_: _: ned.collect-d) lens // (params.drivers or { });
      cyc = cycle lens defs;
      sinks = ned.run drivers cyc;
      # Same Cycle.js fixpoint sources that `ned.run` wires internally, recovered
      # so the unknown-option target check can inspect contribution keys. (Safe for
      # cyclic options: `unknownTargets` reads only contribution KEYS, never the
      # values that would force the throwing sink.)
      sources = mapAttrs (name: drv: drv sinks.${name}) drivers;
      handlers = defaultHandlers // (params.handlers or { });
      # SINGLE KAHN PASS: classify acyclic vs cyclic nodes AND produce topo order.
      # kahnPass runs once over the static dependency graph; both outputs are derived
      # from it: `topoOrder` (emitted nodes, dependency order) for deepSeq pre-force,
      # and `cyclicSet` (unemitted nodes) for cycle detection. No duplicate Kahn.
      #
      # graph keys are restricted to `lens` (declared options) so nodes outside the
      # declared namespace are invisible to the graph traversal, matching the prior
      # behaviour of the two separate passes.
      graph = mapAttrs (n: _: filter (d: lens ? ${d}) ((params.graph or { }).${n} or [ ])) lens;
      kahn = kahnPass graph;
      inherit (kahn) topoOrder cyclicSet;
      # SETTLE-FUEL: any option on / reaching a cycle gets a located
      # `left{why="cycle"}` here and is NEVER read out of `sinks` below — so the
      # "infinite recursion" throw is structurally avoided (no throw, no hang).
      # depsOfGraph reads from `graph` (already lens-filtered above) — no double filter.
      depsOfGraph = n: graph.${n} or [ ];
      cycleLefts = cycleLeftsFrom cyclicSet depsOfGraph (attrNames lens);
      # Read each option's settled Either from the cycle — EXCEPT cycle members,
      # which short-circuit to their located cycle-left (forcing `sinks.${n}` for a
      # cyclic option is exactly the throwing path settle-fuel exists to prevent).
      rawEithers = mapAttrs (
        n: l:
        if cycleLefts ? ${n} then
          cycleLefts.${n}
        else
          head ((ned.ctx-d handlers (ned.collect-d sinks.${n} l)).toList)
      ) lens;
      # Locate blame (spec §10 `{ path, file, got, why }`): stamp each failing
      # option's `left` with its option name as `path` (and a default `file`) when
      # absent, so every error is addressable to its source option. Existing fields
      # (`why`, `got`, conflict `defs`, …) are preserved — `//` only fills holes.
      locate =
        n: e:
        if e ? left && builtins.isAttrs e.left then
          {
            left = {
              path = n;
              file = "<mod>";
            }
            // e.left;
          }
        else
          e;
      eithers = mapAttrs locate rawEithers;
      # Unknown targets win as lefts (merged in over the declared-option eithers).
      # Valid targets = declared options ∪ registered driver channels (`drivers`
      # is `lens`-keyed collectors plus any custom named channels).
      unknowns = unknownTargets drivers defs sources;
      merged = aggregate (eithers // unknowns);
      # STACK-SAFETY: force every settled value to normal form in DEPENDENCY ORDER
      # via builtins.deepSeq, using `topoOrder` from the single Kahn pass above.
      # Without this, forcing merged (via builtins.any/attrValues at aggregate)
      # cascades N-deep through lazy thunk chains → stack overflow at N≈1000.
      # deepSeq is pure strictness: it does NOT change values, only forces them.
      # Pre-force: walk topo order, deepSeq each settled value. This unrolls the
      # entire thunk chain in dependency order without recursion — Nix-stack O(1).
      preForce = builtins.foldl' (acc: n: builtins.deepSeq (rawEithers.${n} or null) acc) null topoOrder;
    in
    builtins.seq preForce (if merged ? left || check == null then merged else check.get merged.right);
in
{
  inherit run cycle aggregate;
}
