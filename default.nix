{
  inputs ? import ./dev/with-inputs.nix { },
  ...
}:
let
  # dnzl is zen's sole runtime dependency. It re-exports the base vocabulary
  # (ned/fx/bend) and the actor vocabulary (actor/reply/become/send/merge),
  # resolving its own transitive deps from `inputs`. No nixpkgs.lib is needed
  # at runtime now that nixmod (the only lib consumer) is gone.
  inherit (import inputs.dnzl { inherit inputs; })
    ned
    fx
    bend
    actor
    reply
    become
    send
    merge
    ;
  readDirImports =
    dir:
    let
      names = builtins.filter (n: builtins.match ".*\\.nix$" n != null) (
        builtins.attrNames (builtins.readDir dir)
      );
    in
    builtins.foldl' (a: n: a // (import (dir + "/${n}") zen)) { } names;
  base = {
    inherit fx ned bend;
  }
  // readDirImports ./nix;
  # zen surface aliases (spec §4): `zen.m` = merge strategies, `zen.t` = types.
  # The dnzl actor vocabulary (`actor`/`become`/`reply`/`merge`) is surfaced so
  # modules can build actor-handle capabilities (spec §4.3 Flavor B). `zen.send`
  # is the TYPED wrapper over dnzl's `send` (a fresh point-to-point session,
  # spec §4.3): given an actor-handle `ref` and `msgs` (a list or a stream), it
  # runs the session and returns the actor's `right` replies as a plain list.
  zen = base // {
    m = base.merge;
    t = base.types;
    nixmod = base.nixmod;
    inherit
      actor
      become
      reply
      ;
    send =
      ref: msgs: (send ref (if msgs ? toList then msgs else ned.st.fromList msgs)).reply.right.toList;
  };
in
zen
