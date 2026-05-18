let
  srt = builtins.sort (a: b: a < b);
  srtByName = builtins.sort (a: b: a.name < b.name);
  check = name: a: b:
    if a == b then { ok = true; msg = "${name}: OK"; }
    else if builtins.isList a && builtins.isList b && srt a == srt b
    then { ok = true; msg = "${name}: OK (order differs)"; }
    else {
      ok = false;
      msg = "${name}: MISMATCH\n  zen=${builtins.toJSON a}\n  np=${builtins.toJSON b}";
    };

  zen = import ./stress-zen.nix;
  np = import ./stress-nixpkgs.nix;

  checks = [
    (check "packages length" (builtins.length zen.packages) (builtins.length np.packages))
    (check "tags length" (builtins.length zen.tags) (builtins.length np.tags))
    (check "tags content" zen.tags np.tags)
    (check "meta.count" zen.meta.count np.meta.count)
    (check "packages names"
      (srt (map (p: p.name) zen.packages))
      (srt (map (p: p.name) np.packages)))
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
{
  pass = failures == [ ];
  total = builtins.length checks;
  failed = builtins.length failures;
  results = map (c: c.msg) checks;
  failMsgs = map (c: c.msg) failures;
}
