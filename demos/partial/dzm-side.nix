# demos/partial/dzm-side.nix
# One bad-typed option among six. nixpkgs aborts the WHOLE config on the throw.
# dzm settles every option independently: the bad one is a located left, the good
# five remain settled values (at r.left.<name>.right) — deploy the good subset.
let
  zen = import ../../. { };
  r = zen.run {
    modules = [{
      options.port    = zen.opt zen.m.unique zen.t.int;
      options.host    = zen.opt zen.m.unique zen.t.str;
      options.debug   = zen.opt zen.m.unique zen.t.bool;
      options.workers = zen.opt zen.m.unique zen.t.int;
      options.prefix  = zen.opt zen.m.unique zen.t.str;
      options.timeout = zen.opt zen.m.unique zen.t.int;
      config.port    = "nope";        # BAD: string for an int option
      config.host    = "localhost";
      config.debug   = true;
      config.workers = 4;
      config.prefix  = "/api";
      config.timeout = 30;
    }];
  };
in {
  located_failure = r.left.errors;     # the ONE bad option, located
  surviving = {                         # the good five, still settled
    host    = r.left.host.right;
    debug   = r.left.debug.right;
    workers = r.left.workers.right;
    prefix  = r.left.prefix.right;
    timeout = r.left.timeout.right;
  };
}
