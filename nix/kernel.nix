zen:
let
  inherit (zen) ned;
  anyLeft = as: builtins.any (v: v ? left) (builtins.attrValues as);
  eachRight = builtins.mapAttrs (_: v: v.right);
  inherit (builtins)
    mapAttrs
    attrNames
    foldl'
    head
    ;

  toSt =
    v:
    if v ? toList then
      v
    else
      ned.st {
        value = v;
        file = "<def>";
        prio = 100;
      };

  applyLenses =
    lens: rawSrcs: mapAttrs (n: src: if lens ? ${n} then src (lens.${n}) else src) rawSrcs;

  step =
    srcs: acc: d:
    let
      s = d srcs;
    in
    foldl' (a: k: a // { ${k} = (a.${k} or ned.st) (toSt s.${k}); }) acc (attrNames s);

  # Default: unresolved conflict returns a negotiating left (no handler installed).
  defaultHandlers = {
    condition =
      { param, state }:
      {
        inherit state;
        resume = {
          restart = "negotiating";
          value = {
            left = {
              why = "negotiating";
              defs = param.data.defs;
            };
          };
        };
      };
  };

  cycle =
    lens: defs: rawSrcs:
    let
      srcs = applyLenses lens rawSrcs;
    in
    foldl' (step srcs) (mapAttrs (_: _: ned.st) lens) defs;

  aggregate =
    eithers: if anyLeft eithers then { left = eithers; } else { right = eachRight eithers; };

  run =
    arg:
    let
      params = if arg ? lens then arg else zen.fromMods arg;
      inherit (params) lens defs;
      check = params.check or null;
      drivers = mapAttrs (_: _: ned.collect-d) lens // (params.drivers or { });
      sinks = ned.run drivers (cycle lens defs);
      handlers = defaultHandlers // (params.handlers or { });
      eithers = mapAttrs (n: l: head ((ned.ctx-d handlers (ned.collect-d sinks.${n} l)).toList)) lens;
      merged = aggregate eithers;
    in
    if merged ? left || check == null then merged else check.get merged.right;
in
{
  inherit run cycle aggregate;
}
