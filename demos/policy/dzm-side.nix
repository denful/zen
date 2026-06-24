# demos/policy/dzm-side.nix
# Same config, two failure POLICIES, chosen only by the handler (Koka: swap the
# interpreter). nixpkgs has one hardcoded throw policy.
let
  zen = import ../../. { };
  mods = [
    {
      options.port = zen.opt zen.m.unique zen.t.int;
      options.workers = zen.opt zen.m.unique zen.t.int;
      options.host = zen.opt zen.m.unique zen.t.str;
      config.port = "nope"; # bad (string for int)
      config.workers = "also-bad"; # bad
      config.host = "localhost"; # good
    }
  ];
  # a "warn-and-continue" policy: each failed option resumes with a safe fallback,
  # the config still settles. The HANDLER is the policy.
  warn =
    { param, state }:
    {
      inherit state;
      resume = {
        value = zen.bend.right 0;
      };
    };
in
{
  collecting = zen.run { modules = mods; }; # default: all errors located
  warnContinue = zen.run {
    modules = mods;
    handlers = {
      typeCheck = warn;
    };
  }; # degrade: settles w/ fallbacks
}
