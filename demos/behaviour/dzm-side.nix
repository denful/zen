# demos/behaviour/dzm-side.nix
# Value-dependent option EXISTENCE via dzm's whole-config check seam (spec §8).
# `enable :: Bool` flips which options the module accepts — actor `become` at the
# config-acceptance level. The dependent type is fx's ACTUAL Σ over Bool with
# LARGE ELIMINATION (`zen.depshape`): the accepted record SHAPE is `snd enable`.
# Errors are DATA (a located left), never an abort.
let
  zen = import ../../. { };
  inherit (zen) fx;
  H = fx.types.hoas;

  # snd enable : record TYPE of {turbo,maxSpeed} for the selected behaviour.
  behaviourShape =
    enable:
    fx.types.mkType {
      name = if enable then "A{turbo,maxSpeed}" else "B{}";
      kernelType = H.any;
      guard =
        b: if enable then b.turbo != null && b.maxSpeed != null else b.turbo == null && b.maxSpeed == null;
    };

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

  tag =
    r:
    if r ? right then
      { accepted = r.right; }
    else
      {
        rejected = r.left.why;
        got = r.left.got;
      };
in
{
  # enable=true → {turbo,maxSpeed} ARE the interface.
  enableTrue = {
    present = tag (run [
      (zen.def {
        enable = true;
        turbo = true;
        maxSpeed = 200;
      })
    ]);
    absent = tag (run [ (zen.def { enable = true; }) ]);
  };
  # enable=false → {turbo,maxSpeed} are NOT the interface (present → located left).
  enableFalse = {
    absent = tag (run [ (zen.def { enable = false; }) ]);
    present = tag (run [
      (zen.def {
        enable = false;
        turbo = true;
        maxSpeed = 200;
      })
    ]);
  };
}
