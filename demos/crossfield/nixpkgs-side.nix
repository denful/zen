# demos/crossfield/nixpkgs-side.nix
#
# nixpkgs cross-field constraint — the evalModules assertions pattern.
#
# NixOS modules express cross-field invariants as assertions:
#   assertions = [{ assertion = <bool>; message = "..."; }];
# When a boolean is false, evalModules throws a single unstructured string
# containing all the human-readable messages concatenated — the call site
# cannot programmatically identify which fields are implicated.
#
# Contrast with dzm: dzm's bend.ensure returns a structured Left carrying
# { why, constraint, fields } so a tool or UI can highlight the exact fields
# without parsing a string.
#
# Additionally, nixpkgs assertions all evaluate (they are a list of booleans
# computed simultaneously), then any failures are thrown together.  dzm's
# bend.pipe SHORT-CIRCUITS on first failure (see crossfield/dzm-side.nix note).
#
# Run:  nix-instantiate --eval --strict --json demos/crossfield/nixpkgs-side.nix | jq .
let
  # Simulate merged module config.
  cfg = {
    protocol = "tcp";
    port     = 80;      # violates "tcp => port > 1024"
  };

  # The assertions list — the nixpkgs idiom for cross-field constraints.
  # Each assertion is a {boolean, string} pair.  No {fields, constraint, ...} record.
  assertions = [
    {
      assertion = !(cfg.protocol == "tcp" && cfg.port <= 1024);
      message   = "tcp needs port > 1024 (got protocol=${cfg.protocol} port=${toString cfg.port})";
    }
  ];

  failedAssertions = builtins.filter (a: !a.assertion) assertions;

  # evalModules aborts the whole eval with a throw — no structured value returned.
  assertionResult =
    if failedAssertions != [ ]
    then throw (builtins.concatStringsSep "\n"
          (map (a: "- ${a.message}") failedAssertions))
    else cfg;
in
{
  # The throw is caught by tryEval so this file evals cleanly.
  # success=false means the assertion fired (a violation occurred).
  forced_throws = builtins.tryEval (builtins.seq assertionResult assertionResult);

  # The failure message — a hand-written string, no structured locus.
  failure_messages_unstructured = map (a: a.message) failedAssertions;

  # The assertion record has no `fields` attribute — only assertion + message.
  has_fields_record = (builtins.elemAt failedAssertions 0) ? fields;

  # Summary of the limitation relative to dzm.
  limitation = {
    failure_signal          = "unstructured throw string (no {why, constraint, fields})";
    fields_programmatically = false;
    tooling_can_highlight   = false;
    recovery_possible       = false;   # throw is fatal; no restart/handler seam
  };
}
