# demos/cycle/dzm-side.nix
# Same mutual option reference: a↔b.
# dzm detects the cycle statically via Kahn topo-sort and returns a located
# left { why = "cycle"; cycle = [...]; } — never throws, never hangs.
let
  zen = import ../../. { };
  r = zen.run {
    modules = [
      {
        options.a = zen.opt zen.m.unique zen.t.int;
        options.b = zen.opt zen.m.unique zen.t.int;
        # mutual reference: a↔b — the static dep graph has a→b→a
        config.a = { b }: b;
        config.b = { a }: a;
      }
    ];
    # Static dependency graph — dzm uses this for Kahn cycle detection
    graph.a = [ "b" ];
    graph.b = [ "a" ];
  };
in
# Returns located cycle blame — both nodes, both cycle paths
{
  a_blame = r.left.a.left;
  b_blame = r.left.b.left;
}
