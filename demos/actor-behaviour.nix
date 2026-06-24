# Value-dependent option EXISTENCE — the actor `become` investor demo.
#
#   nix-instantiate --eval --strict --json demos/actor-behaviour.nix | jq .
#
# An `enable :: Bool` option whose VALUE flips which options the module accepts —
# like an actor `become` swapping its behaviour (and thus its message interface):
#
#   enable = true  → behaviour A: {turbo, maxSpeed} are part of the interface
#                    (present = well-formed; absent = a LOCATED error).
#   enable = false → behaviour B: {turbo, maxSpeed} are NOT part of the interface
#                    (absent = well-formed; present = a LOCATED error).
#
# The dependent type is fx's ACTUAL `Sigma` over `Bool` with LARGE ELIMINATION:
# `Σ (b:Bool) (snd b)`, where `snd true` is the record type with the fields
# PRESENT and `snd false` the record type with them ABSENT. The record SHAPE is
# computed by casing a value — the Martin-Löf device for "which fields exist
# depends on a value". Threaded through dzm's whole-config `check` seam by
# `zen.depshape`. Errors are DATA (a located `left`), never a fatal abort.
#
# HONESTY (level achieved): this flips the accepted-config SHAPE with the value
# (present/absent enforcement) — the strongest RUNNABLE form. It is NOT a literal
# dynamic SCHEMA where the lens key set is itself a function of a settled value:
# that is structurally blocked in dzm for the SAME reason as nixpkgs — the option
# set must be known to build the cycle that settles the value the option set would
# depend on. See the `nixpkgsNote` field.
let
  zen = import ../. { };
  inherit (zen) fx;
  H = fx.types.hoas;

  # The Σ family: `snd enable` is the fx TYPE of the {turbo, maxSpeed} bundle for
  # the behaviour `enable` selects. LARGE ELIMINATION — the record type is chosen
  # by casing the Bool value:
  #   enable = true  → both fields PRESENT (non-null).
  #   enable = false → both fields ABSENT  (null).
  behaviourShape =
    enable:
    fx.types.mkType {
      name = if enable then "Behaviour-A{turbo,maxSpeed}" else "Behaviour-B{}";
      kernelType = H.any;
      guard =
        bundle:
        if enable then
          bundle.turbo != null && bundle.maxSpeed != null
        else
          bundle.turbo == null && bundle.maxSpeed == null;
    };

  # One `zen.run` over the module. `turbo`/`maxSpeed` are declared OPTIONAL
  # (absence settles to null); `depshape` casts `enable` to decide which world is
  # well-formed via the fx Σ above.
  run =
    defs:
    zen.run {
      lens = {
        enable = zen.types.bool;
        turbo = zen.withDefault null zen.types.bool;
        maxSpeed = zen.withDefault null zen.types.int;
      };
      inherit defs;
      check = zen.depshape {
        index = "enable";
        fields = [
          "turbo"
          "maxSpeed"
        ];
        fst = fx.types.Bool;
        snd = behaviourShape;
      };
    };

  # Render an Either as plain JSON-able data (no throw escapes the world).
  show =
    label: r:
    {
      case = label;
    }
    // (
      if r ? right then
        {
          settled = "right";
          shape = r.right;
        }
      else
        {
          settled = "left";
          blame = r.left;
        }
    );
in
{
  nixpkgsNote = "nixpkgs lib.evalModules cannot make option EXISTENCE depend on a value: option DECLARATIONS are static and resolved BEFORE the config fixpoint, so `imports = lib.mkIf cfg.enable [...]` (config-dependent declaration) throws \"infinite recursion encountered\". `mkIf` gates option VALUES, never EXISTENCE. dzm flips the accepted option SHAPE with the value through the whole-config check seam (fx Σ + large elimination).";

  # ── enable = true → BEHAVIOUR A: {turbo, maxSpeed} ARE the interface ─────────
  behaviourA = {
    # present → right (the turbo behaviour is well-formed).
    present_ok = show "enable=true, turbo+maxSpeed present" (run [
      (zen.def {
        enable = true;
        turbo = true;
        maxSpeed = 200;
      })
    ]);
    # absent → LOCATED left (behaviour A REQUIRES the fields).
    absent_rejected = show "enable=true, turbo+maxSpeed absent" (run [ (zen.def { enable = true; }) ]);
  };

  # ── enable = false → BEHAVIOUR B: {turbo, maxSpeed} are NOT the interface ────
  behaviourB = {
    # absent → right (the bare behaviour is well-formed).
    absent_ok = show "enable=false, turbo+maxSpeed absent" (run [ (zen.def { enable = false; }) ]);
    # present → LOCATED left (those options DON'T EXIST in behaviour B).
    present_rejected = show "enable=false, turbo+maxSpeed present" (run [
      (zen.def {
        enable = false;
        turbo = true;
        maxSpeed = 200;
      })
    ]);
  };

  # ── The interface DEPENDS on enable's value (become) ────────────────────────
  # The SAME {turbo,maxSpeed}-present config is ACCEPTED at enable=true and
  # REJECTED at enable=false. The SAME bare config is ACCEPTED at enable=false
  # and REJECTED at enable=true. If existence were value-independent (as in
  # nixpkgs), the pairs would agree; they do not — the accepted option world is
  # `snd enable`. Flip enable → the module has `become` a different behaviour.
  becomeFlip = {
    present_at_true_accepted =
      (run [
        (zen.def {
          enable = true;
          turbo = true;
          maxSpeed = 200;
        })
      ]) ? right;
    present_at_false_rejected =
      (run [
        (zen.def {
          enable = false;
          turbo = true;
          maxSpeed = 200;
        })
      ]) ? left;
    bare_at_false_accepted = (run [ (zen.def { enable = false; }) ]) ? right;
    bare_at_true_rejected = (run [ (zen.def { enable = true; }) ]) ? left;
  };
}
