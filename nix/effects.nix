zen:
let
  inherit (zen) bend ned;
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
}
