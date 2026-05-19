zen:
let
  inherit (zen) bend;
  inherit (zen.merge) unique concat attrs;
  inherit (builtins) isAttrs match toString;

  opt =
    m: t:
    bend.pipe [
      (bend.parse m bend.identity)
      (t.inner or t)
    ];

  submodOf =
    schema:
    let
      innerSchema = builtins.mapAttrs (_: t: t.inner or t) schema;
    in
    {
      get =
        raw:
        if !isAttrs raw then
          bend.left {
            why = "not-an-attrset";
            got = raw;
          }
        else
          (bend.recordAll innerSchema).get raw;
      set = _: bend.right;
    };

  intBetween = lo: hi: bend.ensure (n: n >= lo && n <= hi) "${toString lo}..${toString hi}" bend.int;
  strMatch = pat: bend.ensure (s: match pat s != null) "pattern:${pat}" bend.str;

  # mkT: wraps inner lens with unique merge, attaches .inner for listOf/attrsOf
  mkT = inner: (opt unique inner) // { inherit inner; };

in
{
  inherit opt;

  withDefault = default: lens: {
    get = defs: if defs == [ ] then bend.right default else lens.get defs;
    set = lens.set;
  };

  types = {
    int = mkT bend.int;
    str = mkT bend.str;
    bool = mkT bend.bool;
    float = mkT bend.float;
    any = mkT bend.identity;
    nonEmptyStr = mkT (bend.ensure (s: s != "") "non-empty" bend.str);
    singleLineStr = mkT (strMatch "[^\n]*");
    strMatching = pat: mkT (strMatch pat);
    port = mkT (intBetween 0 65535);
    positiveInt = mkT (bend.ensure (n: n > 0) "positive" bend.int);
    unsignedInt = mkT (bend.ensure (n: n >= 0) "unsigned" bend.int);
    intBetween = lo: hi: mkT (intBetween lo hi);
    nullOr = t: mkT (bend.optional (t.inner or t));
    listOf = t: opt concat (bend.each (t.inner or t));
    attrsOf = t: opt attrs (bend.eachValue (t.inner or t));
    submod = schema: mkT (submodOf schema);
    attrsSubmod = schema: opt attrs (bend.recordAll (builtins.mapAttrs (_: t: t.inner or t) schema));
    sub = opt unique {
      get = v: if v ? left then v else bend.right v;
      set = _: bend.right;
    };
  };
}
