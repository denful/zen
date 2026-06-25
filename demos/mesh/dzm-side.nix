# demos/mesh/dzm-side.nix
#
# THE SYNTHESIS: ONE `zen.run` that NEGOTIATES a conflict (handlers.condition)
# AND PROVES the negotiated config with a dependent type (check = zen.deptype)
# in a single settlement pass.
#
# Story: two modules both set `n` at equal priority (genuine conflict).
# A custom handler resolves the conflict via a `use-value` restart, picking
# n = length(slots) = 2. The dependent check `slots :: Vector n` runs AFTER
# settlement over the RIGHT result and validates internal consistency.
#
# HONEST NOTE: the dependent check runs only when settlement yields a `right`
# (the resolver must produce a concrete value). If the resolver itself failed
# (returned a left), the check would not run — the error already locates the
# conflict, not the type. This is faithful to the architecture: type-proof over
# a successfully negotiated config.
#
# Outcomes:
#   good → resolver computes n=2 → settlement right → Vector 2 holds length-2
#          slots → final right (negotiated AND proven).
#   bad  → resolver picks n=9090 (useLast) → settlement right → Vector 9090
#          REJECTS length-2 slots → located left
#          { why="deptype"; index="n"; indexValue=9090;
#            expected="Vector[9090, Int]"; got=[4040,5050]; path="slots" }.
#
#   nix-instantiate --eval --strict --json demos/mesh/dzm-side.nix
let
  zen = import ../../. { };
  inherit (zen) fx;

  # Dependent family: Vector Int indexed by the negotiated n.
  slotsTypeAt = n: (fx.types.Vector fx.types.Int).apply n;

  # Fixed 2-element slot list — the invariant is n == length slots == 2.
  slots = [
    4040
    5050
  ];

  # ONE zen.run: both seams (handlers + check) in one call.
  mesh =
    resolver:
    zen.run {
      lens = {
        # n is the CONTESTED option — merge.conflict signals a condition the
        # handler must resolve. Two same-priority defs => genuine 2-def conflict.
        n = zen.opt zen.merge.conflict zen.types.int;
        slots = zen.types.listOf zen.types.int;
      };
      defs = [
        (zen.defP 100 {
          n = 8080;
          slots = slots;
        })
        (zen.defP 100 { n = 9090; })
      ];
      # (1) NEGOTIATE: resolve the `n` conflict to ONE value.
      handlers = {
        condition = resolver;
      };
      # (2) PROVE: slots :: Vector n over the NEGOTIATED config.
      check = zen.deptype {
        index = "n";
        depends = "slots";
        fst = fx.types.Int;
        snd = slotsTypeAt;
      };
    };

  # ── resolvers ────────────────────────────────────────────────────────────────

  # GOOD: compute n = length(defs) = 2 via use-value restart.
  # The negotiation lands on 2 — exactly what the dependent type requires.
  resolveToValid = { param, state }: {
    resume = {
      restart = "use-value";
      value = zen.bend.right (builtins.length param.data.defs); # 2 defs => n=2
    };
    inherit state;
  };

  # BAD: useLast picks the order-last surviving def => n=9090.
  # Negotiation SUCCEEDS (right), but Vector 9090 rejects a length-2 list.
  # This is the mandatory non-vacuous negative control.
  resolveToInvalid = zen.resolve.useLast;

  # Render an Either as plain JSON-able data.
  show =
    label: r:
    {
      case = label;
    }
    // (
      if r ? right then
        {
          settled = "right";
          negotiated = r.right;
        }
      else
        {
          settled = "left";
          blame = r.left;
        }
    );
in
{
  good = show "negotiate->n=2, slots length 2 => Vector n holds" (mesh resolveToValid);
  bad = show "negotiate->n=9090, slots length 2 => Vector n REJECTS" (mesh resolveToInvalid);
}
