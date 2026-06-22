zen:
let
  inherit (zen) bend;
  inherit (zen.merge) unique concat attrs;
  inherit (builtins)
    isAttrs
    isFunction
    match
    toString
    sort
    foldl'
    filter
    head
    length
    ;

  # --- mk* overrides (spec §6) — first-class def VALUES. ---------------------
  #
  # The priority/order constants are EXACT nixpkgs (lib/modules.nix:1589-1627):
  #   mkForce=50  bare=100  mkDefault=1000  optionDefault=1500
  #   mkBefore=500  mkAfter=1500  default order=1000
  # `mkOverride n`/`mkOrder n` are the GENERAL forms the named aliases specialize.
  #
  # An override is a TAGGED value the bridge discharges before a Def is built:
  #   mkOverride/mkForce/mkDefault → `{ _zenOverride = { prio; content; }; }`
  #   mkOrder/mkBefore/mkAfter     → `{ _zenOverride = { order; content; }; }`
  #   mkIf cond                    → `{ _zenIf   = { cond; content; }; }`
  #   mkMerge [..]                 → `{ _zenMerge = [ contents ]; }`
  # Tagging (not a bare prio field on the value) keeps user data — a value that
  # happens to contain `prio` — distinguishable from an override wrapper.
  mkOverride = prio: content: { _zenOverride = { inherit prio content; }; };
  mkForce = mkOverride 50;
  mkDefault = mkOverride 1000;
  mkOrder = order: content: { _zenOverride = { inherit order content; }; };
  mkBefore = mkOrder 500;
  mkAfter = mkOrder 1500;
  mkIf = cond: content: { _zenIf = { inherit cond content; }; };
  mkMerge = contents: { _zenMerge = contents; };

  # --- Resolution: priority FILTER + order SORT (spec §6). -------------------
  #
  # Input is the option's `[Def]` (each `{ value, file, prio, order }`). mkIf is
  # already discharged in the bridge (dropped when false), and mkMerge already
  # fanned out, so this stage handles ONLY the priority/order axes:
  #
  #   1. priority is a FILTER, NOT a selector: find the numerically-LOWEST prio
  #      present, then KEEP EVERY def at that prio (drop all higher-numbered).
  #      This is what makes "two mkForce lists concat, a bare list among them is
  #      DROPPED" true — the load-bearing nixpkgs behavior (G1).
  #   2. sort survivors by `order` (stable; lower order first).
  #
  # Survivors stay Def records so the downstream merge strategy reads `.value`.
  # Empty input passes through untouched → the merge strategy raises `required`.
  # Default order for any Def lacking an explicit `order` (legacy `def`/`defP`
  # and kernel `toSt` paths predate the order axis). Mirrors nixpkgs, where an
  # un-ordered def carries the default order 1000.
  resolveDefaultOrder = 1000;
  orderOf = d: d.order or resolveDefaultOrder;

  resolveDefs =
    defs:
    if defs == [ ] then
      [ ]
    else
      let
        minPrio = foldl' (m: d: if d.prio < m then d.prio else m) (head defs).prio defs;
        survivors = filter (d: d.prio == minPrio) defs;
      in
      sort (a: b: orderOf a < orderOf b) survivors;

  # resolveStage :: bend lens over [Def] — prepended to `opt`'s pipe so it runs
  # BEFORE the merge strategy. `get` never fails (no throw); it returns the
  # filtered+sorted survivor list for the strategy to merge.
  resolveStage = {
    get = defs: bend.right (resolveDefs defs);
    set = _: bend.right;
  };

  # typed :: lens -> lens
  # Wrap a type lens so a SCALAR type rejection carries the located-blame shape
  # (spec §10: `{ why = "type"; got; ... }`). The bare `bend` scalar parsers reject
  # with the raw offending value (`bend.left v`); we lift that into `{ why = "type";
  # got = v; }` so blame is structured + classifiable. A composite lens
  # (listOf/attrsOf/submod) already rejects with a structured record (a `recordAll`
  # attrset, `{ why = "not-an-attrset"; }`, …); we DETECT that (left is an attrset
  # already carrying `why`/per-field lefts) and pass it through unwrapped so nested
  # blame is preserved. `path`/`file` are attached at the kernel boundary, where the
  # option name is in scope.
  typed =
    lens:
    let
      structured = v: isAttrs v && (v ? why || v ? errors || v ? left);
    in
    {
      get =
        s:
        let
          r = lens.get s;
        in
        if r ? left && !(structured r.left) then
          bend.left {
            why = "type";
            got = r.left;
          }
        else
          r;
      set = lens.set;
    };

  opt =
    m: t:
    bend.pipe [
      resolveStage
      (bend.parse m bend.identity)
      (typed (t.inner or t))
    ];

  submodOf =
    schema:
    let
      innerSchema = builtins.mapAttrs (_: t: t.inner or t) schema;
    in
    {
      get =
        raw:
        if !isAttrs raw then
          bend.left {
            why = "not-an-attrset";
            got = raw;
          }
        else
          (bend.recordAll innerSchema).get raw;
      set = _: bend.right;
    };

  # capLens :: why -> lens. A capability lens: accept ANY function, REJECT a
  # non-function (located `{ why; got; }`), and BOX the accepted function into
  # `{ __cap = fn; }` so it survives the cycle as opaque data (see types.fn/actor).
  # The bridge unboxes `__cap` at the dep-read site.
  capLens = why: {
    get =
      v:
      if isAttrs v && v ? __cap then
        bend.right v
      else if isFunction v then
        bend.right { __cap = v; }
      else
        bend.left {
          inherit why;
          got = v;
        };
    set = _: bend.right;
  };

  intBetween = lo: hi: bend.ensure (n: n >= lo && n <= hi) "${toString lo}..${toString hi}" bend.int;
  strMatch = pat: bend.ensure (s: match pat s != null) "pattern:${pat}" bend.str;

  # mkT: wraps inner lens with unique merge, attaches .inner for listOf/attrsOf
  mkT = inner: (opt unique inner) // { inherit inner; };

in
{
  inherit
    opt
    mkOverride
    mkForce
    mkDefault
    mkOrder
    mkBefore
    mkAfter
    mkIf
    mkMerge
    ;

  withDefault = default: lens: {
    get = defs: if defs == [ ] then bend.right default else lens.get defs;
    set = lens.set;
  };

  types = {
    int = mkT bend.int;
    str = mkT bend.str;
    bool = mkT bend.bool;
    float = mkT bend.float;
    any = mkT bend.identity;
    nonEmptyStr = mkT (bend.ensure (s: s != "") "non-empty" bend.str);
    singleLineStr = mkT (strMatch "[^\n]*");
    strMatching = pat: mkT (strMatch pat);
    port = mkT (intBetween 0 65535);
    positiveInt = mkT (bend.ensure (n: n > 0) "positive" bend.int);
    unsignedInt = mkT (bend.ensure (n: n >= 0) "unsigned" bend.int);
    intBetween = lo: hi: mkT (intBetween lo hi);
    nullOr = t: mkT (bend.optional (t.inner or t));
    listOf =
      t:
      let
        el = bend.each (t.inner or t);
      in
      (opt concat el) // { inner = el; };
    attrsOf =
      t:
      let
        el = bend.eachValue (t.inner or t);
      in
      (opt attrs el) // { inner = el; };
    # Capability value types (spec §4.3). A capability flows through the typed
    # dep graph as an option VALUE — never a stringly ref. `fn` is a function
    # capability (Flavor A, applied directly by a consumer); `actor` is a dnzl
    # actor-handle (Flavor B, queried via `zen.send`). Both are functions at the
    # Nix level (a dnzl actor-handle = `actor behaviour` partially applied), so
    # the type lens admits any function and rejects non-functions; the SEMANTIC
    # distinction is the consumer (direct application vs `zen.send`).
    #
    # BOXED so the cycle carries an OPAQUE value: a bare function would be
    # intercepted by the `ned.st` stream functor (it routes attrset-arg lambdas
    # like a dnzl actor's `{inbox}:` through the contextual-fn path, forcing the
    # arg — kernel.nix:275). Boxing into `{ __cap = fn; }` makes "a raw function
    # inside a cycle stream" structurally unrepresentable for capabilities; the
    # bridge's edge-local dep-projection UNBOXES `__cap` so a consumer still sees
    # the bare fn (`mkHome u`, `zen.send counter`). Type-enforced, not by convention.
    fn = mkT (capLens "fn");
    actor = mkT (capLens "actor");
    submod = schema: mkT (submodOf schema);
    attrsSubmod = schema: opt attrs (bend.recordAll (builtins.mapAttrs (_: t: t.inner or t) schema));
    # submodule option (spec §4/§5) — a CHILD CYCLE crossing the boundary. The
    # contribution is `{ __sub = <inner Either>; }` (sub.nix): a UNIFORM Either,
    # `{right=cfg}` on a settled child, `{left=blame}` on inner failure. This lens
    # unwraps `__sub` SYMMETRICALLY — it returns the inner Either AS-IS for both
    # branches, so success and failure travel the identical path (the deleted
    # zen-old asymmetry was a `if v ? left` value-level selector here). A bare value
    # lacking `__sub` (defensive / legacy direct contribution) is accepted as a
    # plain right. Inner `config` reads are PLAIN throughout (bridge `settledOf`).
    sub = opt unique {
      get = v: if isAttrs v && v ? __sub then v.__sub else bend.right v;
      set = _: bend.right;
    };
  };
}
