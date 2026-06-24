# TRUE Π-type (dependent FUNCTION type) through dzm `zen.run` options — demo.
#
#   nix-instantiate --eval --strict --json demos/pitype.nix | jq .
#
# nixpkgs `lib.types.functionTo retType` carries ONLY the codomain (the return
# type): it wraps a function and checks RESULTS. It has NO slot for the DOMAIN
# (input type), and cannot make the return TYPE depend on the input VALUE.
#
# MLTT's `Π(x:A).B(x)` states BOTH the domain A AND a codomain family B(x). This
# demo threads fx's ACTUAL `Pi`/`Vector` constructor (nix-effects MLTT
# types.dependent) through dzm's whole-config `check` seam via `zen.pitype`.
#
# fx checks a raw Nix lambda at the ELIMINATION site (`pi.checkAt f arg`): it
# applies f to the argument and checks `arg : A` then `f arg : B(arg)`. The pure
# guard alone is only `isFunction` (a lambda carries no type annotation), so
# `zen.pitype` runs the effectful elimination and collapses it to an Either.
#
#   DOMAIN:   correct-type arg → right;   wrong-type arg → LOCATED left (domain)
#   CODOMAIN: result : B(arg)  → right;   wrong result   → LOCATED left (codomain)
#   DEPENDENT: mkVec 3 → length-3 ok; change n → required length changes.
let
  zen = import ../. { };
  inherit (zen) fx;

  IntT = fx.types.Int;

  # The dependent codomain family: fx's canonical length-indexed vector at the
  # argument value. `vecAt n = Vector Int n` — an MLTT dependent type object.
  vecAt = n: (fx.types.Vector IntT).apply n;

  # (1) DOMAIN demo — a function option `f :: Int → Int` and the argument `x` it
  #     is applied to. nixpkgs `functionTo` cannot constrain the DOMAIN.
  runDom =
    fnVal: argVal:
    zen.run {
      lens = {
        f = zen.types.any;
        x = zen.types.any;
      };
      defs = [
        (zen.def {
          f = fnVal;
          x = argVal;
        })
      ];
      check = zen.pitype {
        fn = "f";
        arg = "x";
        domain = IntT;
        codomain = _: IntT;
      };
    };

  # (2) DEPENDENT FUNCTION demo — `mkVec :: (n:Int) → Vector n`. The result TYPE
  #     is computed from the argument VALUE.
  runVec =
    fnVal: nVal:
    zen.run {
      lens = {
        mkVec = zen.types.any;
        n = zen.types.any;
      };
      defs = [
        (zen.def {
          mkVec = fnVal;
          n = nVal;
        })
      ];
      check = zen.pitype {
        fn = "mkVec";
        arg = "n";
        domain = IntT;
        codomain = vecAt;
      };
    };

  double = x: x * 2;
  mkVecOk = n: builtins.genList (i: i) n; # returns a length-n vector
  mkVecBad2 = _: [
    1
    2
  ]; # ALWAYS length-2, ignores n

  # Render an Either as plain JSON-able data (no throw escapes the world; a
  # `right` config may carry a function value, which is summarised, not dumped).
  show =
    label: r:
    {
      case = label;
    }
    // (
      if r ? right then
        { settled = "right"; }
      else
        {
          settled = "left";
          blame = r.left;
        }
    );
in
{
  note = "nixpkgs lib.types.functionTo carries ONLY the codomain (return type) — it has no slot for the DOMAIN, and cannot make the return TYPE depend on the input VALUE. dzm carries Π(x:A).B(x) because fx's Pi elimination (checkAt) runs in the whole-config check seam: it checks BOTH `arg : A` and `f arg : B(arg)`, B being a function of the value.";

  # --- DOMAIN: nixpkgs functionTo cannot reject a wrong-type argument -------
  domain = {
    # f : Int → Int applied to 21 (Int) → right.
    correct = show "f:Int->Int applied to 21" (runDom double 21);
    # f : Int → Int applied to "no" (String) → located left at the `x` option,
    # site="domain". THIS is the functionTo gap: it can only check the result.
    wrong_arg = show "f:Int->Int applied to \"no\" (wrong domain)" (runDom double "no");
    # f returns a String when Int is expected → located left, site="codomain".
    wrong_result = show "f returns String, Int expected (codomain)" (runDom (_: "str") 21);
  };

  # --- DEPENDENT FUNCTION: return TYPE computed from input VALUE -------------
  dependent = {
    # mkVec 3 returns [0 1 2] (length 3); codomain Vector[3] accepts → right.
    correct = show "mkVec 3 -> length-3 vector" (runVec mkVecOk 3);
    # a length-2-returning fn at n=3: codomain Vector[3] rejects → located left
    # whose `expected` NAMES the fx type at the resolved index (Vector[3, Int]).
    wrong_length = show "len-2 fn at n=3 (codomain Vector[3])" (runVec mkVecBad2 3);
  };

  # --- DEPENDENCE: change n → the required length changes --------------------
  # The SAME length-2 function is ACCEPTED at n=2 and REJECTED at n=3 — the
  # codomain is `Vector[n]`, computed from n's value, not a constant.
  dependence = {
    len2_at_n2 = show "len-2 fn at n=2 (accepted)" (runVec mkVecBad2 2);
    len2_at_n3 = show "len-2 fn at n=3 (rejected)" (runVec mkVecBad2 3);
  };
}
