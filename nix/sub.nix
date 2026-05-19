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
      value = result.right or result;
    in
    {
      ${name} = ned.st {
        inherit value;
        file = "<sub:${name}>";
        prio = 100;
      };
    };
}
