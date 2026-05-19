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

  # reconcile :: init → (state → item → { state; result }) → ST item → ST result
  reconcile =
    init: step: source:
    source (ned.st.scanl (acc: step acc.state) {
      state = init;
      result = null;
    }) (ned.st.flatMap (acc: if acc.result != null then ned.st.fromList [ acc.result ] else ned.st));

  # satisfy :: (T | pred) → lens  (T with .check, or a boolean predicate function)
  satisfy = T: bend.satisfy (if T ? check then T.check else T);
}
