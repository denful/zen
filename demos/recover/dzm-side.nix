# demos/recover/dzm-side.nix
# Conflicting definitions for one option (port 8080 vs 9090, both int).
# nixpkgs evalModules throws "conflicting definition values" and dies.
# dzm: the conflict SIGNALS a CL-style condition; a resolver restart RESUMES
# settlement. Same config, three outcomes, chosen only by the handler.
let
  zen = import ../../. { };
  mk = resolver: zen.run {
    lens = {
      port = zen.opt zen.merge.conflict zen.types.int;
      host = zen.opt zen.merge.unique zen.types.str;
    };
    defs = [
      (zen.def { port = 8080; host = "localhost"; })
      (zen.def { port = 9090; })
    ];
    handlers = { condition = resolver; };
  };
in {
  useFirst = mk zen.resolve.useFirst;   # -> right { port = 8080; host = "localhost"; }
  useLast  = mk zen.resolve.useLast;    # -> right { port = 9090; host = "localhost"; }
  reject   = mk zen.resolve.reject;     # -> left { errors=[{path=port;why=conflict;defs}]; host settles }
}
