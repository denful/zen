# TRUE dependent type through a dzm `zen.run` option — investor demo.
#
#   nix-instantiate --eval --strict --json demos/deptype.nix | jq .
#
# An option `n :: Int` and an option `items :: Vector n` (a list of EXACTLY `n`
# elements). The TYPE of `items` is `snd n` — a function of the VALUE of `n`.
# This threads fx's ACTUAL `Vector`/`Sigma` constructor (nix-effects MLTT
# types.dependent) through dzm's whole-config `check` hook via `zen.deptype`.
#
#   correct (length == n) → settles `right`
#   wrong   (length != n) → settles a LOCATED `left` (data, never a throw)
#   change n → the required length changes (the type references n's value)
#
# nixpkgs `lib.evalModules` STRUCTURALLY cannot express this: a module `type` is
# a fixed value resolved before any option's value is known — there is no seam
# where one option's resolved value parameterises another option's type.
let
  zen = import ../. { };
  inherit (zen) fx;

  # The dependent family: fx's canonical length-indexed vector at the index.
  # `snd n = Vector Int n` — an MLTT dependent type object, not a predicate.
  vectorIntAt = n: (fx.types.Vector fx.types.Int).apply n;

  run =
    nVal: itemsVal:
    zen.run {
      lens = {
        n = zen.types.int;
        items = zen.types.listOf zen.types.int;
      };
      defs = [
        (zen.def {
          n = nVal;
          items = itemsVal;
        })
      ];
      check = zen.deptype {
        index = "n";
        depends = "items";
        fst = fx.types.Int;
        snd = vectorIntAt;
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
          value = r.right;
        }
      else
        {
          settled = "left";
          blame = r.left;
        }
    );
in
{
  note = "nixpkgs lib.evalModules cannot express a type referencing another option's value (a module `type` is resolved before any option value is known); dzm carries `items :: Vector n` because the dependent fx type lives in the whole-config check seam.";

  # n = 3, items length 3 → right.
  correct = show "n=3, items length 3" (
    run 3 [
      1
      2
      3
    ]
  );

  # n = 3, items length 2 → located left (why/path/index — DATA, not abort).
  wrong = show "n=3, items length 2" (
    run 3 [
      1
      2
    ]
  );

  # The type DEPENDS on n: same length-2 items accepted at n=2, rejected at n=3.
  dependence = {
    n2_len2 = show "n=2, items length 2" (
      run 2 [
        1
        2
      ]
    );
    n3_len2 = show "n=3, items length 2" (
      run 3 [
        1
        2
      ]
    );
  };
}
