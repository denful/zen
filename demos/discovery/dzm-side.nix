# demos/discovery/dzm-side.nix
# Capability discovery: providers publish a capability; a client discovers it BY
# NAME, never referencing the provider modules. A broker (a selector over a
# registrations stream — withPeers grouped by capability, highest priority wins)
# wires them at settle-time. Flip a provider's priority → the client rewires with
# ZERO consumer edits. Producer/consumer fully decoupled.
let
  zen = import ../../. { };
  inherit (zen.ned) st;

  # broker :: [registration] -> registration -> ST resolved
  # Groups by capability; within each group the highest-priority registration
  # wins. Only the winner emits a row (losers stay silent — mirrors leader-election).
  broker =
    peers: reg:
    let
      winner = builtins.head (builtins.sort (a: b: a.priority > b.priority) peers);
    in
    if reg.name == winner.name then
      st {
        capability = winner.capability;
        resolvedFrom = winner.name;
        endpoint = winner.endpoint;
        losers = map (r: r.endpoint) (builtins.filter (r: r.name != winner.name) peers);
      }
    else
      st; # losers are silent; their endpoints appear in winner.losers

  # discover :: registration -> registration -> { cacheUrl, resolvedFrom, losers }
  # Client logic is IDENTICAL regardless of which provider wins.
  discover =
    provA: provB:
    let
      regs = st provA provB;
      resolved = (st.withPeers (r: r.capability) broker regs).toList;
      cacheEntry = builtins.head (builtins.filter (e: e.capability == "cache") resolved);
    in
    {
      cacheUrl = cacheEntry.endpoint;
      resolvedFrom = cacheEntry.resolvedFrom;
      losers = cacheEntry.losers;
    };

  providerA = prio: { name = "providerA"; capability = "cache"; endpoint = "redis://10.0.0.1"; priority = prio; };
  providerB =       { name = "providerB"; capability = "cache"; endpoint = "memcached://10.0.0.2"; priority = 5; };
in
{
  # providerA wins (priority 10 > 5) → redis
  resolved = discover (providerA 10) providerB;
  # SAME client logic; only providerA priority changed (3 < 5) → memcached wins
  rewired  = discover (providerA 3)  providerB;
}
