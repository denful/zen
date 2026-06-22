zen:
# bridge.nix — the actor-cycle bridge (R1: CONSTANT case).
#
# Desugars each `config.<name>` entry of a module into a dnzl `actorDef`: a
# contribution to option <name>, resolved later by that option's lens.
#
#   - LITERAL  `config.<name> = <value>`  → a constant-replying actorDef whose
#     inbox is EMPTY (no deps). It contributes a constant Def `{value,file,prio}`.
#   - FUNCTION `config.<name> = {deps}: expr` → an actorDef whose inbox is EXACTLY
#     `builtins.functionArgs body` (the edge-local law). R1 only requires the
#     literal path to WORK; the function path is wired structurally (functionArgs
#     → inbox) but its body resolution is R2.
#
# EDGE-LOCAL INVARIANT (the O(N²)-avoiding law): a contribution's inbox is its
# declared dependency set — NEVER the full set of settled options. `inboxOf`
# below is `builtins.functionArgs` for a function body and `{}` for a literal;
# there is no all-settled fan-in anywhere in this file.
let
  inherit (zen) ned;
  inherit (builtins)
    isFunction
    isAttrs
    functionArgs
    mapAttrs
    attrNames
    foldl'
    concatMap
    head
    ;

  # A bare definition's priority + default order (nixpkgs-grade; spec §6).
  barePrio = 100;
  defaultOrder = 1000;

  # mkDef :: file -> { prio, order, content } -> Def
  # A Def is a settled contribution `{ value, file, prio, order }` (spec §6).
  mkDef =
    file:
    {
      prio,
      order,
      content,
    }:
    {
      value = content;
      inherit file prio order;
    };

  # toDef :: file -> value -> [Def] (singleton)
  # A literal contribution → one bare-priority/default-order Def. Kept for the
  # exported surface; the contribute path uses `defsOf` (which handles mk*).
  toDef = file: value: [
    (mkDef file {
      prio = barePrio;
      order = defaultOrder;
      content = value;
    })
  ];

  # --- mk* DISCHARGE (spec §6) ----------------------------------------------
  #
  # A contributed VALUE may be a tagged override (see api.nix). `flatten` peels
  # the tags into a flat list of leaf contributions `{ prio, order, content }`,
  # carrying the priority/order axes DOWN through nesting:
  #   _zenOverride { prio?; order?; content } → set that axis, recurse on content
  #   _zenIf { cond; content }                → recurse on content if cond, else DROP
  #   _zenMerge [ .. ]                         → fan out: concat each child's leaves
  #   (anything else)                          → a single leaf with the current axes
  # mkIf discharged here (dropped when false) BEFORE any Def exists; mkMerge fans
  # out to multiple Defs. Priority/order from the OUTERMOST wrapper of each axis
  # win (nixpkgs: the inner override of the same axis is not re-applied once set).
  flattenOverride =
    prio: order: v:
    if isAttrs v && v ? _zenOverride then
      let
        o = v._zenOverride;
      in
      flattenOverride (o.prio or prio) (o.order or order) o.content
    else if isAttrs v && v ? _zenIf then
      (if v._zenIf.cond then flattenOverride prio order v._zenIf.content else [ ])
    else if isAttrs v && v ? _zenMerge then
      concatMap (flattenOverride prio order) v._zenMerge
    else
      [
        {
          inherit prio order;
          # BOX a function contribution (spec §4.3 capability) so it enters the
          # cycle as OPAQUE data. A bare attrset-arg lambda (e.g. a dnzl actor's
          # `{inbox}:`) is otherwise intercepted by the `ned.st` stream functor
          # and reaches the type lens as a stream — not a function — and is
          # rejected. Boxing at the leaf, BEFORE any stream transport, makes that
          # structurally impossible; `t.fn`/`t.actor` accept the box and the
          # dep-projection (`settledOf`) unboxes `__cap` for the consumer.
          content = if isFunction v then { __cap = v; } else v;
        }
      ];

  # defsOf :: file -> value -> [Def]
  # Discharge mk* on a contributed value, then build a Def per surviving leaf.
  # mkIf-false ⇒ [] (no Def); mkMerge ⇒ several Defs; bare ⇒ one Def.
  defsOf = file: value: map (mkDef file) (flattenOverride barePrio defaultOrder value);

  # inboxOf :: body -> { <dep> = true; ... }
  # The EDGE-LOCAL inbox of one config entry. A literal has an empty inbox; a
  # `{deps}: expr` body has EXACTLY its `functionArgs`-named deps. This is the
  # whole edge-local routing — there is no separate `reads` field, and never an
  # all-settled fan-in.
  inboxOf = body: if isFunction body then functionArgs body else { };

  # settledOf :: srcs -> dep -> settled value
  # Read ONE inbox dependency's settled VALUE out of the cycle sources. `srcs` here
  # is the LENS-APPLIED source set the kernel cycle threads in (see
  # kernel.cycle: `srcs = applyLenses lens rawSrcs`); each `srcs.<k>` is therefore
  # an `ned.st` stream whose head is that option's settled `Either`
  # (`{ right = <val>; }` once the option resolves, `{ left = <blame>; }` on
  # failure). For the common case (spec §10: deps carry the settled VALUE, not the
  # raw Either) we project `.right`. Forcing `head (srcs.<k>.toList)` forces EXACTLY
  # that one option's resolution and NOTHING else — this single read IS the
  # edge-local law in action.
  settledOf =
    srcs: k:
    let
      either = head (srcs.${k}.toList);
      v = either.right or null;
    in
    # UNBOX a capability (spec §4.3): `t.fn`/`t.actor` box their function into
    # `{ __cap = fn; }` so it survives the cycle as opaque data (a bare fn would
    # be intercepted by the stream functor). The consumer reads the bare fn.
    if isAttrs v && v ? __cap then v.__cap else v;

  # contribute :: { srcs, file } -> name -> body -> ST Def
  # Turn one `config.<name> = body` entry into its Def contribution STREAM. The
  # stream carries 0+ Defs so mk* fan-out/gating is structural:
  #   - mkMerge → several Defs (each a stream element).
  #   - mkIf false → ZERO Defs (empty stream) — the value is gated out, though the
  #     TARGET key still exists (unknown-option checking still sees it).
  #   - literal / single override / function → one Def.
  # Resolution paths:
  #   - literal: constant-replier — value IS the (post-discharge) literal.
  #   - function (`{deps}: expr`): edge-local. Its inbox is `inboxOf body`; the body
  #     is applied to a projection carrying the SETTLED VALUE of each inbox
  #     dependency, read ONLY for the inbox keys via `settledOf` — never
  #     `attrNames srcs`, so a sibling option outside the inbox is never forced
  #     (the O(N²)-avoiding, divergence-isolating edge-local invariant).
  # mk* is discharged on the body RESULT (`defsOf`), so `mkForce ({deps}: ...)` is
  # not a thing — overrides wrap the contributed VALUE, deps wrap via functionArgs.
  contribute =
    { srcs, file }:
    _name: body:
    let
      inbox = inboxOf body;
      # Edge-local projection: ONLY the inbox keys are read from srcs, never all.
      deps = builtins.listToAttrs (
        map (k: {
          name = k;
          value = settledOf srcs k;
        }) (attrNames inbox)
      );
      value = if isFunction body then body deps else body;
    in
    ned.st.fromList (defsOf file value);

  # actorDef :: module -> (srcs -> { <opt> = ST Def; ... })
  # The adapter. Given a module's `config`, produce the cycle-shaped def-producer:
  # a function from the settled `srcs` to a per-option attrset of Def-stream
  # contributions. `srcs` is supplied by the kernel cycle (collect-d sinks); each
  # contribution forces ONLY its own edge-local inbox out of it. The kernel's
  # `step` concats each per-key stream, so mkMerge's multiple Defs all reach the
  # option's lens via collect-d's `.toList`.
  actorDef =
    {
      config ? { },
      file ? "<mod>",
    }:
    srcs: mapAttrs (name: body: contribute { inherit srcs file; } name body) config;

in
{
  inherit
    actorDef
    inboxOf
    toDef
    defsOf
    flattenOverride
    ;
}
