# demos/actor/dzm-side.nix
# Running-total actor via dzm's typed actor capability (spec §4.3 Flavor B).
# A dnzl actor-handle (zen.t.actor) is passed through the typed dep graph.
# zen.send runs a fresh point-to-point session: [10,20,30] → [10,30,60].
let
  zen = import /home/vic/hk/workspace/demos-ws { };

  # The running-total actor: reply.right the new cumulative total, become the
  # next state. A genuine dnzl actor-handle — stateful via become.
  counterActor = zen.actor (
    let
      go = total: amt: (zen.reply.right (total + amt)) // (zen.become (go (total + amt)));
    in
    go 0
  );

  r = zen.run {
    modules = [
      {
        options.counter = zen.opt zen.m.unique zen.t.actor;
        options.batch = zen.t.listOf zen.t.int;
        options.totals = zen.t.listOf zen.t.int;
        config.counter = { }: counterActor;
        config.batch = [
          10
          20
          30
        ];
        config.totals = { counter, batch }: zen.send counter batch;
      }
    ];
  };
in
# totals = [10, 30, 60] — every intermediate state, not just the final
builtins.removeAttrs r.right [ "counter" ]
