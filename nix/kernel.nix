zen:
let
  inherit (zen) bend ned;
  inherit (builtins)
    mapAttrs
    concatMap
    attrNames
    any
    ;

  cycle =
    lens: defs: srcs:
    let
      allItems = concatMap (d: (d srcs).toList) defs;
      grouped = builtins.groupBy (d: d.name) allItems;
    in
    {
      config = mapAttrs (name: l: l.get (grouped.${name} or [ ])) lens;
    };

  aggregateL = bend.parse (
    cfg:
    if any (n: cfg.${n} ? left) (attrNames cfg) then
      bend.left cfg
    else
      bend.right (mapAttrs (_: v: v.right) cfg)
  ) bend.identity;

in
{
  run = { lens, defs }: aggregateL.get (ned.run { config = x: x; } (cycle lens defs)).config;
}
