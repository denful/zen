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
}
