# demos/deprecord/dzm-side.nix
#
# GENUINELY DEPENDENT RECORD: addr's TYPE is computed from kind's VALUE.
#
# `kind :: enum["static","dynamic","dhcp"]` and `addr :: snd(kind)` where
#   snd "static"  = IPv4  (String matching d.d.d.d)
#   snd "dynamic" = IPv4  (same)
#   snd "dhcp"    = Null  (must be absent / null)
#
# This is a real Sigma type:  Σ (k : Kind), snd(k)
#   fst.check  validates kind's membership
#   (snd fst).check  validates addr against the type SELECTED by kind's value
#
# KEY PROOF: the SAME addr value gets different verdicts depending on kind's
# value — not a predicate, but a TYPE that varies with the witness.
#
# nixpkgs lib.evalModules CANNOT express this: a module option's `type` is
# a fixed value resolved before any option value is known.  The nixpkgs idiom
# is an `assertion` (a rebuild-time boolean side-check), not a dependent type.
#
# Run:  nix-instantiate --eval --strict --json demos/deprecord/dzm-side.nix | jq .
let
  zen = import ../../. { };
  inherit (zen) fx;
  T = fx.types;

  # The dependent family  snd : kindValue -> Type  (Sigma second component).
  # Returns a DIFFERENT fx Type per value of kind — this is the dependence.
  ipv4 = T.refined "IPv4" T.String (T.matching "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+");
  addrTypeOf =
    kind:
    if kind == "dhcp" then T.Null   # dhcp => addr must be null/absent
    else ipv4;                      # static | dynamic => addr must be an IPv4

  run =
    kindVal: addrVal:
    zen.run {
      lens = {
        # kind: enum over the three tags (widest static slot; Sigma fst below narrows it)
        kind = zen.types.strMatching "static|dynamic|dhcp";
        # addr: nullOr str is the widest static slot; snd(kind) decides the actual type
        addr = zen.types.nullOr zen.types.str;
      };
      defs = [
        (zen.def {
          kind = kindVal;
          addr = addrVal;
        })
      ];
      check = zen.deptype {
        index   = "kind";
        depends = "addr";
        # fst: the fx ENUM type (refined String, exactly the three tags)
        fst = T.refined "Kind" T.String (T.oneOfStr [ "static" "dynamic" "dhcp" ]);
        # snd: the dependent function — returns a DIFFERENT fx Type per kind value
        snd = addrTypeOf;
      };
    };

  show =
    label: r:
    { case = label; }
    // (if r ? right
        then { settled = "right"; value = r.right; }
        else { settled = "left";  blame = r.left;  });
in
{
  # kind="static", addr valid IPv4 -> right
  static_ok  = show "kind=static, addr=10.0.0.1"  (run "static" "10.0.0.1");

  # kind="static", addr not an IPv4 -> located left (blame shows expected=IPv4 type)
  static_bad = show "kind=static, addr=not-an-ip" (run "static" "not-an-ip");

  # kind="dhcp", addr=null -> right (snd dhcp = Null, null is correct)
  dhcp_ok    = show "kind=dhcp, addr=null"         (run "dhcp" null);

  # kind="dhcp", addr="10.0.0.1" -> located left (dhcp forbids an address)
  dhcp_bad   = show "kind=dhcp, addr=10.0.0.1"    (run "dhcp" "10.0.0.1");

  # THE TYPE-FROM-VALUE PROOF: same addr, kind flips the required type -> flips verdict.
  #
  #   addr=null    : right at dhcp (snd=Null accepts null)
  #                  left  at static (snd=IPv4 rejects null)
  #   addr=10.0.0.1: right at static (snd=IPv4 accepts it)
  #                  left  at dhcp   (snd=Null rejects any string)
  same_addr_kind_flips = {
    null_at_dhcp    = show "addr=null    @ kind=dhcp"    (run "dhcp"   null);
    null_at_static  = show "addr=null    @ kind=static"  (run "static" null);
    ip_at_static    = show "addr=10.0.0.1 @ kind=static" (run "static" "10.0.0.1");
    ip_at_dhcp      = show "addr=10.0.0.1 @ kind=dhcp"   (run "dhcp"   "10.0.0.1");
  };
}
