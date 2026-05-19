zen:
let
  inherit (zen) bend fx;
  inherit (builtins)
    head
    sort
    length
    foldl'
    map
    concatLists
    any
    mapAttrs
    ;

  emptyRequired = bend.left { why = "required"; };
  # Sort only when more than one def — single-element is the common case.
  byPrio = defs: if length defs == 1 then head defs else head (sort (a: b: a.prio < b.prio) defs);
  byPrio' = defs: if length defs == 1 then head defs else head (sort (a: b: a.prio > b.prio) defs);

  # Guard: empty list → required error; otherwise call f.
  withRequired = f: defs: if defs == [ ] then emptyRequired else f defs;

  oneOrLeft =
    why:
    withRequired (
      defs: if length defs == 1 then bend.right (head defs).value else bend.left { inherit why defs; }
    );

  unique = oneOrLeft "conflict";
  # conflict: signals a condition effect so ctx-d handlers can resolve it.
  conflict = withRequired (
    defs:
    if length defs == 1 then
      bend.right (head defs).value
    else
      fx.bind (fx.effects.conditions.signal "conflict" { inherit defs; } [
        "use-first"
        "use-last"
        "reject"
      ]) (r: fx.pure r.value)
  );
  first = withRequired (defs: bend.right (byPrio defs).value);
  last = withRequired (defs: bend.right (byPrio' defs).value);
  concat = defs: bend.right (concatLists (map (d: d.value) defs));
  attrs = defs: bend.right (foldl' (a: d: a // d.value) { } defs);

  # Shared shape for condition handlers (fx.effects.conditions protocol).
  mkRestart =
    restart: mkValue:
    { param, state }:
    {
      resume = {
        inherit restart;
        value = mkValue param.data.defs;
      };
      inherit state;
    };

in
{
  merge = {
    inherit
      unique
      first
      last
      concat
      attrs
      conflict
      ;
  };

  resolve = {
    useFirst = mkRestart "use-first" (defs: bend.right (byPrio defs).value);
    useLast = mkRestart "use-last" (defs: bend.right (byPrio' defs).value);
    reject = mkRestart "reject" (
      defs:
      bend.left {
        why = "conflict";
        inherit defs;
      }
    );
  };

  test = {
    isError = r: r ? left;
    isOk = r: r ? right;
    fieldError = r: field: r ? left && r.left.${field} ? left;
    isConflict = r: field: r ? left && r.left.${field} ? left && r.left.${field}.left.why == "conflict";
    isRequired = r: field: r ? left && r.left.${field} ? left && r.left.${field}.left.why == "required";
  };

}
