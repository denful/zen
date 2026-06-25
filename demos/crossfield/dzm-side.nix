# demos/crossfield/dzm-side.nix
#
# CROSS-FIELD INVARIANT: "if protocol=tcp then port must be > 1024"
# The violation is LOCATED to the implicated fields (not a thrown string).
#
# dzm uses bend.ensure which, on failure, returns a structured Left carrying
# { why, constraint, fields } — the caller knows WHICH fields caused the
# violation and WHAT the constraint was, without parsing a string.
#
# HONESTY NOTE — short-circuit behaviour:
#   bend.pipe SHORT-CIRCUITS on first violation: if two ensure checks are
#   composed and the first fails, the second is never evaluated.  The demo
#   (caseD) shows this explicitly.  This is still a strict improvement over
#   nixpkgs: the failure is STRUCTURED and LOCATED, not a thrown string.
#   Full accumulation (all-at-once) would require a different combinator.
#
# Run:  nix-instantiate --eval --strict --json demos/crossfield/dzm-side.nix | jq .
let
  zen = import ../../. { };
  inherit (zen) bend;

  # Shared cross-field check: "tcp implies port > 1024"
  tcpPortCheck = bend.ensure (cfg: !(cfg.protocol == "tcp" && cfg.port <= 1024)) {
    why = "cross-field";
    constraint = "tcp:port>1024";
    fields = [
      "protocol"
      "port"
    ];
  } bend.identity;

  mk =
    protocol: port:
    zen.run {
      lens = {
        protocol = zen.types.str;
        port = zen.types.port;
      };
      defs = [
        (zen.def { protocol = protocol; })
        (zen.def { port = port; })
      ];
      check = tcpPortCheck;
    };

  show =
    label: r:
    {
      case = label;
    }
    // (
      if r ? right then
        {
          settled = "right";
          value = r.right;
        }
      else
        {
          settled = "left";
          blame = r.left;
        }
    );

  # Two-constraint pipe to demonstrate short-circuit explicitly.
  # constraint1: port > 1024  (fields=[port])
  # constraint2: protocol != "ftp"  (fields=[protocol])
  # With port=80 AND protocol="ftp": only the FIRST failure is returned.
  twoCheckPipe = bend.pipe [
    (bend.ensure (cfg: cfg.port > 1024) {
      why = "cross-field";
      constraint = "port>1024";
      fields = [ "port" ];
    } bend.identity)
    (bend.ensure (cfg: cfg.protocol != "ftp") {
      why = "cross-field";
      constraint = "no-ftp";
      fields = [ "protocol" ];
    } bend.identity)
  ];

  caseD = zen.run {
    lens = {
      protocol = zen.types.str;
      port = zen.types.port;
    };
    defs = [
      (zen.def { protocol = "ftp"; })
      (zen.def { port = 80; })
    ];
    check = twoCheckPipe;
  };
in
{
  # tcp+80 -> located Left: blame carries {why, constraint, fields=[protocol,port]}
  violation = show "tcp+80 => cross-field violation located to fields" (mk "tcp" 80);

  # tcp+8080 -> Right: port above 1024, invariant holds
  ok = show "tcp+8080 => ok (port>1024)" (mk "tcp" 8080);

  # udp+80 -> Right: udp is exempt from the tcp-only constraint
  exempt = show "udp+80 => exempt (constraint only applies to tcp)" (mk "udp" 80);

  # Short-circuit demo: both constraints fail, only first is returned.
  # Located to fields=[port], NOT fields=[protocol] — second check never runs.
  pipe_short_circuit = show "ftp+80: two failures, only first returned (short-circuit)" caseD;
}
