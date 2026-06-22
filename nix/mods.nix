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

  # mkDef :: module -> (srcs -> { <opt> = Def; ... })
  # Evaluate a module's whole-config fixpoint (module-as-function + a `config`
  # that is itself a function receive the settled `plain` projection — legacy
  # surface), THEN hand the resulting `config` attrset to the bridge
  # (`zen.actorDef`), which performs the EDGE-LOCAL per-key desugar: literals
  # become constant Defs; per-key `{deps}: expr` get an inbox of exactly their
  # `functionArgs` deps. The bridge is the single desugar point for `config`.
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
    zen.actorDef {
      config = cfg;
      file = "<mod>";
    } srcs;

  # graphOf :: module -> { <opt> = [ depOpt ]; ... }
  # The STATIC dependency graph of one module's `config` (spec §5 "static option
  # identity"): each `config.<name> = { deps }: expr` body's dependency set is its
  # `functionArgs`, read WITHOUT forcing any settled value (functionArgs is purely
  # structural). Literals contribute no edges. This graph is what settle-fuel's
  # bounded cycle-detector walks (kernel.nix): a cycle in it (a→b→a) is a genuine
  # cyclic option reference that the lazy fixpoint would otherwise THROW on.
  #
  # Only the surface form — `config` a PLAIN attrset — is analyzed. A module that
  # is itself a function, or whose `config` is a function of the whole settled
  # projection (legacy whole-config fixpoint), is NOT statically inspectable
  # without forcing values, so it contributes no static edges (the fuel falls back
  # to lazy evaluation for those; R7's cycle tests use the surface form).
  graphOf =
    m:
    if isRaw m || isFunction m then
      { }
    else
      let
        e = eval m;
        cfg = e.config or { };
      in
      if isFunction cfg then
        { }
      else
        mapAttrs (
          _: body: if isFunction body then builtins.attrNames (builtins.functionArgs body) else [ ]
        ) cfg;

in
{
  fromMods =
    mods:
    let
      lens = foldl' (a: m: if isRaw m then a else a // (eval m).options or { }) { } mods;
      defs = map (m: if isRaw m then (if isFunction m then m else _: m) else mkDef m) mods;
      # Merge every module's static config-dep graph. One option may be contributed
      # to by several modules; later modules' edges union in (a // b keeps both
      # since keys are distinct contribution targets, and same-key bodies share the
      # same option's dep set in practice). `graph` rides in the params record so
      # `run` can detect cycles BEFORE forcing the throwing lazy fixpoint.
      graph = foldl' (a: m: a // graphOf m) { } mods;
    in
    {
      inherit lens defs graph;
    };

  defP =
    prio: attrs: _:
    mapAttrs (
      _: value:
      ned.st {
        inherit value prio;
        file = "<def>";
        order = 1000;
      }
    ) attrs;

  def = zen.defP 100;
}
