zen:
let
  inherit (zen) bend ned fx;
  inherit (builtins) mapAttrs;

in
{
  # provide :: bindings → def → def
  provide =
    bindings: def: srcs:
    mapAttrs (_: ned.ctx-d bindings) (def srcs);

  # request :: { name = fn; } → def  (name is the attrset key)
  request = attrs: _srcs: mapAttrs (_: fn: ned.st fn) attrs;

  # reconcile :: init → (acc → item → acc) → [item] → acc   (spec §4.2)
  #
  # Stateful fold surfaced as a typed combinator. The dnzl actor engine
  # (`ned.st.scanl` = `actor` + `become`) runs UNDERNEATH, but the collection
  # is a DETERMINISTIC list — never an inbox-arrival stream — so the output is a
  # pure function of the input SET, not of arrival order (spec §4.2 determinism
  # guard; spec §14 "become-order nondeterminism" mitigation).
  #
  # DETERMINISM GUARD (type-enforced at the SURFACE): `coll` MUST be a list. A
  # non-list (an unordered attrset, a raw stream, …) has no deterministic
  # iteration order, so it is REJECTED with a located `left` rather than folded
  # in some accidental order. This is the negative control's target — a user CAN
  # construct the rejected case (it is not an engine-internal handle).
  #
  # On success the FINAL accumulator is returned RAW (not Either-wrapped) so the
  # §4.2 call site reads `(zen.reconcile init step names).out` directly. `scanl`
  # emits `[init, step init c0, step (…) c1, …]`; the last element is the fold
  # result (and is `init` for an empty list).
  reconcile =
    init: step: coll:
    if !(builtins.isList coll) then
      {
        left = {
          why = "non-deterministic-fold";
          got = coll;
        };
      }
    else
      let
        accs = ((ned.st.fromList coll).scanl step init).toList;
      in
      builtins.elemAt accs (builtins.length accs - 1);

  # satisfy :: (T | pred) → lens  (T with .check, or a boolean predicate function)
  satisfy = T: bend.satisfy (if T ? check then T.check else T);

  # deptype — a TRUE dependent type as a whole-config `check` (spec §8).
  #
  # WHY a `check`, not a per-option `satisfy`: a value-dependent type is, by
  # definition, a type that REFERENCES another value. The per-option `satisfy`
  # lens is unary (`T.check :: value -> bool`) — it sees ONE option's value and
  # structurally CANNOT name a sibling. A Σ-type's second component is a TYPE
  # FAMILY `snd :: fstValue -> Type`; resolving it requires BOTH the index value
  # and the dependent value at once. The `check` hook (kernel.nix:327/395) is the
  # only seam that receives the whole settled config `{ <opt> = value; ... }`, so
  # it is where a genuine Martin-Löf Σ-type can live. We thread fx's ACTUAL
  # `Sigma` constructor (nix-effects types.dependent) — `snd fstValue` is the fx
  # MLTT type object for the dependent field, not a hand-rolled boolean. The TYPE
  # of `snd` is literally a function of the value of `fst`.
  #
  # deptype :: {
  #   index   :: opt name supplying the value the dependent type is indexed by;
  #   depends :: opt name whose TYPE is `snd (cfg.${index})`;
  #   fst     :: fx type of the index value (e.g. fx.types.Int);
  #   snd     :: indexValue -> fx type for the dependent field (the Σ family);
  #   why?    :: blame tag (default "deptype");
  # } -> check-lens  ({ get; set })
  #
  # Pass  → `bend.right cfg` (the §8 introduction form: a proof the pair inhabits
  #         the Σ-type). Fail → a LOCATED `bend.left { why; path; got; ... }`
  #         (not a throw) — `path` is the dependent option, `index`/`expected`
  #         name the broken dependency so blame is addressable (spec §10).
  deptype =
    {
      index,
      depends,
      fst,
      snd,
      why ? "deptype",
    }:
    let
      sigma = fx.types.Sigma {
        inherit fst snd;
        universe = 0;
      };
    in
    {
      get =
        cfg:
        let
          # Pack the settled config into the Σ-type's pair value. `fst` is the
          # index, `snd` the dependent field; `snd`'s fx type is `snd cfg.${index}`.
          paired = {
            fst = cfg.${index};
            snd = cfg.${depends};
          };
        in
        if fx.types.check sigma paired then
          bend.right cfg
        else
          bend.left {
            inherit why index;
            path = depends;
            indexValue = cfg.${index};
            got = cfg.${depends};
            expected = (snd cfg.${index}).name;
          };
      set = _: bend.right;
    };

  # depshape — value-dependent option EXISTENCE via fx Σ + LARGE ELIMINATION
  # (spec §8, the behaviour-`become` framing).
  #
  # WHY this is distinct from `deptype`: `deptype` fixes WHICH options exist and
  # makes one option's TYPE depend on another's value. `depshape` makes the
  # accepted SHAPE of the config — which of the `fields` may/must be present —
  # depend on the `index` option's value. The dependent type `snd indexValue` is
  # not a type ON a fixed field but a type OVER A RECORD whose very inhabitants
  # are casing the index: `snd true` admits records where the fields are PRESENT,
  # `snd false` admits records where they are ABSENT. That is Martin-Löf LARGE
  # ELIMINATION — a record TYPE computed by casing a value — the exact MLTT
  # device for "which fields exist depends on a value" (Σ(b:Bool)(if b then {…}
  # else {})). It is the closest faithful approximation, AT THE ACCEPTED-CONFIG
  # LEVEL, of an actor `become` that swaps its option interface per message.
  #
  # The lens declaration itself is STATIC (the dzm/nixpkgs-shared lazy-fixpoint
  # constraint: the option set must be known to build the cycle that settles the
  # value the option set would depend on — see kernel.nix run/cycle). So `fields`
  # are declared OPTIONAL (`zen.withDefault null …`): absence settles to `null`,
  # presence to the value, and `depshape` casts the index to decide which world
  # is well-formed. enable=false + a field present ⇒ a LOCATED left (the field
  # must NOT exist in that behaviour); enable=true + a field absent ⇒ a LOCATED
  # left (the behaviour requires it). Flip `index`, the accepted option world
  # flips.
  #
  # depshape :: {
  #   index   :: opt name whose VALUE selects the behaviour (the Σ first comp);
  #   fields  :: [opt name] — the dependent bundle whose EXISTENCE is governed;
  #   fst     :: fx type of the index value (e.g. fx.types.Bool);
  #   snd     :: indexValue -> fx type of the `fields` RECORD (the Σ family /
  #              large elimination: typically present-when-true, absent-when-false);
  #   why?    :: blame tag (default "behaviour-shape").
  # } -> check-lens ({ get; set }).
  #
  # Pass → `bend.right cfg`. Fail → LOCATED `bend.left { why; path; index;
  # indexValue; got; expected }` (DATA, never a throw): `path` lists the governed
  # fields, `indexValue` is the behaviour selector, `got` the offending bundle,
  # `expected` the fx type name of the well-formed shape at that index.
  depshape =
    {
      index,
      fields,
      fst,
      snd,
      why ? "behaviour-shape",
    }:
    let
      sigma = fx.types.Sigma {
        inherit fst snd;
        universe = 0;
      };
      bundleOf =
        cfg:
        builtins.listToAttrs (
          map (f: {
            name = f;
            value = cfg.${f};
          }) fields
        );
    in
    {
      get =
        cfg:
        let
          bundle = bundleOf cfg;
          # The Σ pair: `fst` is the behaviour selector, `snd` the governed-field
          # record. `snd`'s fx type is `snd cfg.${index}` — the record SHAPE for
          # this behaviour, computed by LARGE ELIMINATION on the index value.
          paired = {
            fst = cfg.${index};
            snd = bundle;
          };
        in
        if fx.types.check sigma paired then
          bend.right cfg
        else
          bend.left {
            inherit why index;
            path = fields;
            indexValue = cfg.${index};
            got = bundle;
            expected = (snd cfg.${index}).name;
          };
      set = _: bend.right;
    };

  # pitype — a TRUE Π-type (dependent FUNCTION type) as a whole-config `check`
  # (spec §8). Where `deptype` carries a Σ-type (a dependent PAIR), `pitype`
  # carries a Π-type (a dependent FUNCTION): one option holds a FUNCTION and
  # another holds the ARGUMENT it is applied to, and the function's codomain
  # TYPE is a function of the argument's VALUE.
  #
  # WHY THIS BEATS nixpkgs `lib.types.functionTo`: `functionTo retType` has a
  # SINGLE slot — the codomain (return type). It wraps the function and checks
  # RESULTS; the DOMAIN (input type) is structurally inexpressible (no slot for
  # it), and a value-dependent codomain (return type computed from the input
  # VALUE, e.g. `(n:Int) -> Vector n`) is doubly inexpressible. MLTT's
  # `Π(x:A).B(x)` states BOTH the domain A AND a codomain family B(x).
  #
  # WHY EFFECTFUL, not a pure `fx.types.check`: a Π-type is a HIGHER-ORDER
  # contract (Findler & Felleisen 2002). Its pure guard (`fx.types.check piT f`)
  # is ONLY `builtins.isFunction` — it CANNOT see the domain or codomain (a raw
  # Nix lambda carries no type annotation). The domain+codomain are verified at
  # the ELIMINATION site via `pi.checkAt f arg`, which APPLIES the function to a
  # concrete argument: it sends a `typeCheck` effect for `arg : domain`, then
  # (on pass) for `f arg : codomain arg` — the codomain is `codomain arg`, a
  # genuine function of the input VALUE (dependent.nix:157-190). We RUN that
  # effectful elimination through an error-collecting handler and collapse it to
  # a located Either, so the whole-config `check` seam (kernel.nix:327/395) sees
  # a `right`/`left` exactly like `deptype`.
  #
  # pitype :: {
  #   fn       :: opt name holding the FUNCTION value (the Π inhabitant);
  #   arg      :: opt name holding the ARGUMENT the function is applied to;
  #   domain   :: fx type of the argument (the Π domain A, e.g. fx.types.Int);
  #   codomain :: argValue -> fx type for the result (the Π family B(x));
  #   why?     :: blame tag (default "pitype").
  # } -> check-lens  ({ get; set })
  #
  # Pass  → `bend.right cfg` (the §8 elimination is well-typed: `arg : A` and
  #         `fn arg : B(arg)`). Fail → a LOCATED `bend.left { why; path; site;
  #         ... }` — `site` is "domain" | "codomain" | "shape", `path` names the
  #         offending option, so blame is addressable (spec §10). The codomain
  #         `expected` is the fx type name at the RESOLVED argument value, which
  #         is what makes the dependence visible.
  pitype =
    {
      fn,
      arg,
      domain,
      codomain,
      why ? "pitype",
    }:
    let
      pi = fx.types.Pi {
        inherit domain codomain;
        universe = 0;
      };
      # Collecting handler: a failing typeCheck effect appends its `context`
      # (e.g. "Π domain (…)" / "Π codomain (…)") to state; a passing one
      # resumes silently. Empty state ⟺ the elimination is well-typed.
      collect =
        comp:
        fx.handle {
          handlers.typeCheck =
            { param, state }:
            if param.type.check param.value then
              {
                resume = true;
                inherit state;
              }
            else
              {
                resume = false;
                state = state ++ [ param.context ];
              };
          state = [ ];
        } comp;
      # Classify the first failing context into a blame `site`. The contexts are
      # fx's own (dependent.nix:163/171/185); we match on the discriminating
      # word rather than the full string so the blame is robust to the Π name.
      # `builtins.match` (anchored) gives a pure substring test with no nixpkgs
      # `lib` dependency. NOTE: "codomain" CONTAINS "domain", so the codomain
      # case MUST be tested first.
      hasInfix = needle: hay: builtins.match ".*${needle}.*" hay != null;
      siteOf =
        ctx:
        if hasInfix "codomain" ctx then
          "codomain"
        else if hasInfix "domain" ctx then
          "domain"
        else
          "shape";
    in
    {
      get =
        cfg:
        let
          f = cfg.${fn};
          a = cfg.${arg};
          # Run the dependent ELIMINATION check `fn arg` and gather any blame.
          fails = (collect (pi.checkAt f a)).state;
        in
        if fails == [ ] then
          bend.right cfg
        else
          let
            firstCtx = builtins.head fails;
            site = siteOf firstCtx;
          in
          bend.left {
            inherit why site;
            # The offending option: the argument for a domain fault, the
            # function for a codomain/shape fault (its result was ill-typed).
            path = if site == "domain" then arg else fn;
            argValue = a;
            # The codomain type RESOLVED at the argument value — names the fx
            # MLTT object the result was checked against (proves dependence).
            expected = (codomain a).name;
          };
      set = _: bend.right;
    };
}
