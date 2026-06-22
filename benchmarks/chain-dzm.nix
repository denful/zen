# CHAIN fixture — zen (edge-local engine).
#
# The O(N^2) discriminator (PERF P0a): N options in a LINEAR CHAIN where option
# k's config READS option k-1 — a real cross-option edge per node.
#
#   opt_0 = 0
#   opt_k = { opt_{k-1} }: opt_{k-1} + 1     (k = 1..N)
#
# => opt_k == k. Final config has N+1 options, opt_N == N.
#
# zen's idiom is the PER-KEY edge-local projection `config.<k> = {dep}: expr`,
# whose inbox is EXACTLY its functionArgs dep (one prior option). The claim under
# test: zen forces O(edges)=O(N) total, NOT O(N x modules)=O(N^2).
#
# Invoke: nix-instantiate --eval --strict --argstr N 1000 chain-zen.nix
{ N }:
let
  zen = import ../. { };
  n = if builtins.isInt N then N else builtins.fromJSON N;

  # option name for index i. Plain identifiers (o0, o1, ...) so they are valid
  # both as option keys and as lambda argument (dependency) names.
  nm = i: "o${toString i}";

  # One module per option. Module 0 is the constant root; module k reads o_{k-1}.
  modules = builtins.genList (
    i:
    let
      key = nm i;
    in
    {
      options.${key} = zen.opt zen.m.unique zen.t.int;
      config.${key} =
        if i == 0 then
          0
        else
          # edge-local: inbox = exactly { o_{i-1} }
          let
            prev = nm (i - 1);
          in
          (args: args.${prev} + 1);
    }
  ) (n + 1);
in
zen.run { inherit modules; }
