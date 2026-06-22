zen:
let
  inherit (zen) ned;
  inherit (builtins)
    isList
    mapAttrs
    map
    head
    ;

in
{
  # zen.sub { name = modules-or-params; }
  sub =
    attrs:
    let
      name = builtins.head (builtins.attrNames attrs);
      arg = attrs.${name};
      params = if isList arg then zen.fromMods arg else arg;
      inherit (params) lens defs;
      context = params.context or null;
      check = params.check or null;
    in
    outerSrcs:
    let
      defs' =
        if context == null then
          defs
        else
          map (def: srcs: mapAttrs (_: ned.ctx-d (context outerSrcs)) (def srcs)) defs;

      innerSinks = zen.cycle lens defs' (mapAttrs (_: ned.collect-d) innerSinks);
      innerEithers = mapAttrs (n: l: head ((ned.collect-d innerSinks.${n} l).toList)) lens;

      innerMerged = zen.aggregate innerEithers;
      result = if innerMerged ? left || check == null then innerMerged else check.get innerMerged.right;
      # SUBMODULE = CHILD CYCLE, Either-asymmetry DELETED (spec §4/§5).
      #
      # zen-old contributed `result.right or result` — a PLAIN config attrset on
      # success but the RAW `{left=...}` Either on failure — forcing `types.sub`'s
      # lens to re-inspect `if v ? left` to tell the two cases apart (the
      # asymmetry: strip-then-reinspect). Here the child cycle's aggregate `result`
      # is ALWAYS a uniform Either (`{right=cfg}` | `{left=blame}`), boxed as
      # `{ __sub = <either>; }` and crossed UNIFORMLY. `types.sub` unwraps `__sub`
      # the SAME way for both branches (no `v ? left` selector) — consistent with
      # the bridge's edge-local message normalization. Inner `config` bodies still
      # read PLAIN settled values throughout (via the bridge's `settledOf`
      # `.right`-projection — never the raw inner Either).
    in
    {
      ${name} = ned.st {
        value = {
          __sub = result;
        };
        file = "<sub:${name}>";
        prio = 100;
      };
    };
}
