# demos/blame/dzm-side.nix
# Same two options (port, workers) both given wrong types.
# dzm zen.run collects ALL errors — both surface in left.errors.
let
  zen = import /home/vic/hk/workspace/demos-ws { };
  r = zen.run {
    modules = [
      {
        options.port = zen.opt zen.m.unique zen.t.int;
        options.workers = zen.opt zen.m.unique zen.t.int;
        config.port = "not-a-number"; # wrong: string, expects int
        config.workers = "also-not-a-number"; # wrong: string, expects int
      }
    ];
  };
in
# Returns ALL errors — both faults in left.errors, never aborts.
r.left.errors
