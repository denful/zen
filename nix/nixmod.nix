zen:
let
  inherit (zen) bend ned;
  inherit (builtins)
    isAttrs
    isFunction
    concatLists
    foldl'
    attrNames
    intersectAttrs
    sort
    filter
    isString
    split
    head
    tail
    groupBy
    ;

  # "a.b.c" → ["a" "b" "c"]
  splitDot = k: filter isString (split "\\." k);

  setPath =
    path: val: acc:
    let
      k = head path;
      rest = tail path;
    in
    acc // { ${k} = if rest == [ ] then val else setPath rest val (acc.${k} or { }); };

  unflatten = flat: foldl' (acc: k: setPath (splitDot k) flat.${k} acc) { } (attrNames flat);

  # nixpkgs type → merge strategy
  strat =
    t:
    let
      n = if t == null || !isAttrs t then "" else t.name or "";
    in
    if n == "listOf" || n == "lazyListOf" then
      "concat"
    else if n == "attrsOf" || n == "lazyAttrsOf" || n == "attrs" then
      "attrs"
    else
      "first";

  # option → bend lens: [Def] → Either value error
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
        bend.right (concatLists (map (x: x.value) defs))
      else if s == "attrs" then
        bend.right (foldl' (a: x: a // x.value) { } defs)
      else
        bend.right (head (sort (a: b: a.prio < b.prio) defs)).value
    ) bend.identity;

  # flatten options tree → { "dot.path" → bend_lens }
  flatLens =
    pfx: opts:
    foldl' (
      acc: k:
      let
        v = opts.${k};
        p = if pfx == "" then k else "${pfx}.${k}";
      in
      if (v._type or "") == "option" then
        acc // { ${p} = optL v; }
      else if isAttrs v then
        acc // flatLens p v
      else
        acc
    ) { } (attrNames opts);

  # sparse config walk → [{name, value, file, prio}]
  walkCfg =
    lens: cfg: file:
    let
      go =
        pre: val:
        concatLists (
          map (
            k:
            let
              p = if pre == "" then k else "${pre}.${k}";
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
      cfg = if result ? right then unflatten result.right else { };
      mkArgs = {
        inherit lib;
        config = cfg;
      }
      // specialArgs;
      mods = map (norm mkArgs) modules;
      lens = foldl' (a: m: a // flatLens "" (m.options)) { } mods;
      defs = map (m: _: ned.st.fromList (walkCfg lens (m.config) "<mod>")) mods;
      result = zen.run { inherit lens defs; };
    in
    {
      config = cfg;
    };
}
