zen:
let
  inherit (zen) bend ned;
  inherit (zen.merge) concat attrs;
  byPrio =
    defs:
    if builtins.length defs == 1 then
      builtins.head defs
    else
      builtins.head (builtins.sort (a: b: a.prio < b.prio) defs);
  inherit (builtins)
    isAttrs
    isFunction
    concatLists
    foldl'
    attrNames
    intersectAttrs
    mapAttrs
    filter
    isString
    split
    head
    tail
    groupBy
    map
    ;

  # flat dotted-path helpers
  splitDot = k: filter isString (split "\\." k);
  joinPath = pre: k: if pre == "" then k else "${pre}.${k}";
  setPath =
    path: val: acc:
    let
      k = head path;
      rest = tail path;
    in
    acc // { ${k} = if rest == [ ] then val else setPath rest val (acc.${k} or { }); };
  unflatten = flat: foldl' (acc: k: setPath (splitDot k) flat.${k} acc) { } (attrNames flat);

  stratMap = {
    listOf = "concat";
    lazyListOf = "concat";
    attrsOf = "attrs";
    lazyAttrsOf = "attrs";
    attrs = "attrs";
  };
  strat =
    t:
    let
      n = if t == null || !isAttrs t then "" else t.name or "";
    in
    stratMap.${n} or "first";

  # build a lens from a nixpkgs option
  optL =
    opt:
    let
      s = strat (opt.type or null);
      d = opt.default or null;
    in
    bend.parse (
      defs:
      if defs == [ ] then
        if d != null then bend.right d else bend.left { why = "required"; }
      else if s == "concat" then
        concat defs
      else if s == "attrs" then
        attrs defs
      else
        bend.right (byPrio defs).value
    ) bend.identity;

  # flatten nixpkgs options attrset → { "a.b" = lens }, accumulator threaded
  flatLens =
    pfx: acc: opts:
    foldl' (
      acc: k:
      let
        v = opts.${k};
        p = joinPath pfx k;
      in
      if (v._type or "") == "option" then
        acc // { ${p} = optL v; }
      else if isAttrs v then
        flatLens p acc v
      else
        acc
    ) acc (attrNames opts);

  # walk config attrset → list of Def records
  walkCfg =
    lens: cfg: file:
    let
      go =
        pre: val:
        concatLists (
          map (
            k:
            let
              p = joinPath pre k;
            in
            if lens ? ${p} then
              [
                {
                  name = p;
                  value = val.${k};
                  inherit file;
                  prio = 100;
                }
              ]
            else if isAttrs (val.${k} or null) then
              go p val.${k}
            else
              [ ]
          ) (attrNames val)
        );
    in
    go "" cfg;

  # normalise a module (function or attrset)
  norm =
    mkArgs: m:
    let
      raw = if isFunction m then m (intersectAttrs (builtins.functionArgs m) mkArgs) else m;
    in
    {
      options = { };
      config = { };
    }
    // raw;

in
{
  nixmod.evalModules =
    {
      lib,
      modules,
      specialArgs ? { },
      ...
    }:
    let
      # All configs known upfront — no DI. Use bend lenses directly (no ned.run).
      cfg = if merged ? right then unflatten merged.right else { };
      mkArgs = {
        inherit lib;
        config = cfg;
      }
      // specialArgs;
      mods = map (norm mkArgs) modules;
      lens = foldl' (acc: m: flatLens "" acc (m.options)) { } mods;
      # Collect all {name;value;file;prio} items from all modules
      allItems = concatLists (map (m: walkCfg lens (m.config) "<mod>") mods);
      byOpt = groupBy (item: item.name) allItems;
      # Apply each lens directly to its list of Def records
      eithers = mapAttrs (name: l: l.get (byOpt.${name} or [ ])) lens;
      merged = zen.aggregate eithers;
    in
    {
      config = cfg;
    };
}
