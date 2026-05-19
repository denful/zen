zen:
let
  inherit (zen) ned;
  inherit (builtins)
    isFunction
    mapAttrs
    foldl'
    map
    ;

  eval = m: if isFunction m then m { } else m;
  isRaw =
    m:
    let
      e = eval m;
    in
    !(e ? options) && !(e ? config && !(e.config ? toList));

  toDef =
    file: v:
    ned.st {
      value = v;
      inherit file;
      prio = 100;
    };

  mkDef =
    m: srcs:
    let
      getVal =
        v:
        let
          e = if v ? toList then builtins.head v.toList else v;
        in
        e.right or null;
      plain = mapAttrs (_: getVal) srcs;
      e = if isFunction m then m plain else m;
      cfg = if isFunction (e.config or { }) then e.config plain else e.config or { };
    in
    mapAttrs (_: toDef "<mod>") cfg;

in
{
  fromMods =
    mods:
    let
      lens = foldl' (a: m: if isRaw m then a else a // (eval m).options or { }) { } mods;
      defs = map (m: if isRaw m then (if isFunction m then m else _: m) else mkDef m) mods;
    in
    {
      inherit lens defs;
    };

  defP =
    prio: attrs: _:
    mapAttrs (
      _: value:
      ned.st {
        inherit value prio;
        file = "<def>";
      }
    ) attrs;

  def = zen.defP 100;
}
