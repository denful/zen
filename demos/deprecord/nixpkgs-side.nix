# demos/deprecord/nixpkgs-side.nix
#
# WHY nixpkgs lib.evalModules CANNOT express a dependent record field.
#
# In NixOS modules, every option's `type` is a fixed Nix value that is
# resolved when the module system constructs the option tree — BEFORE any
# option VALUE is known.  There is no seam where one option's resolved value
# parameterises another option's type.
#
# The closest nixpkgs idiom is an `assertion`:
#   assertions = [{ assertion = cond; message = "..."; }];
# which evalModules evaluates AFTER all values are merged, then throws an
# UNSTRUCTURED string if the boolean is false.  That is a side-check, not a
# type: the field `addr` still has ONE fixed type (nullOr str) regardless of
# `kind`'s value.
#
# Concretely:
#   - addr's type is always `nullOr str` — it does not change with kind.
#   - The constraint is expressed as a boolean predicate with a hand-written
#     error string, not as a type object.
#   - The failure signal is a thrown string (no {path, expected, got} record).
#   - A toolchain consuming the failure cannot programmatically extract which
#     fields are implicated or what type was expected.
#
# Run:  nix-instantiate --eval --strict --json demos/deprecord/nixpkgs-side.nix | jq .
let
  # Simulate the merged config a module system would produce.
  # addr's type is FIXED as nullOr str — it does not depend on kind's value.
  cfg = {
    kind = "static";
    addr = null; # null is accepted by the static type (nullOr str) ...
  };

  # ... but null is WRONG for kind=static: we need an IPv4.
  # nixpkgs expresses this as an assertion — a rebuild-time boolean side-check.
  assertions = [
    {
      # The type of addr is always the same; only the boolean differs.
      assertion =
        if cfg.kind == "dhcp" then
          cfg.addr == null
        else
          cfg.addr != null
          && builtins.isString cfg.addr
          && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" cfg.addr != null;
      message =
        "addr type depends on kind: kind=${cfg.kind} requires "
        + (if cfg.kind == "dhcp" then "null" else "an IPv4 string")
        + " but got: ${if cfg.addr == null then "<null>" else cfg.addr}";
    }
  ];

  failedAssertions = builtins.filter (a: !a.assertion) assertions;

  # evalModules throws this unstructured string — no {path, expected, got}.
  assertionResult =
    if failedAssertions != [ ] then
      throw (builtins.concatStringsSep "\n" (map (a: "- ${a.message}") failedAssertions))
    else
      cfg;
in
{
  # 1. What nixpkgs knows about addr's type: ONE fixed type, independent of kind.
  addr_type_is_fixed = "nullOr str — the same type regardless of kind's value";

  # 2. The constraint mechanism: a boolean predicate, not a type.
  constraint_mechanism = "assertion (boolean side-check evaluated at rebuild)";

  # 3. The failure signal: a thrown string — no structured locus.
  #    tryEval catches the throw so this file evals cleanly.
  failure_signal = builtins.tryEval (builtins.seq assertionResult assertionResult);

  # 4. No fields attribute in the failure — tooling cannot extract which fields failed.
  has_structured_locus = false;

  # 5. The failure message is available only as an opaque string inside the throw.
  #    (Shown here as what nixpkgs would produce, captured in failure_signal.value
  #    which is false when throw fires — the message is lost to the caller.)
  limitation = {
    can_express_dependent_type = false;
    failure_carries_fields_record = false;
    failure_carries_expected_type = false;
    idiom = "assertion: boolean predicate + unstructured string throw";
  };
}
