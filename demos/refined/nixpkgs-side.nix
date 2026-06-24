# demos/refined/nixpkgs-side.nix
#
# Foil: lib.types.ints.between 1024 65535 on port = 80.
# nixpkgs aborts with a THROWN STRING; the type name and bounds are buried
# in that string, not recoverable as data. builtins.tryEval catches the
# throw but loses the message. The error text is visible on stderr only.
#
# Contrast with dzm-side.nix: the rejection is a LOCATED left attrset —
# { why = "refined"; name = "Port"; got = 80; } — addressable as data.
let
  lib = import <nixpkgs/lib>;

  # Attempt evaluation of port = 80 against ints.between 1024 65535.
  # tryEval catches the throw; success = false means nixpkgs rejected it.
  # The message ("A definition for option `port' is not of type
  # `integer between 1024 and 65535 (both inclusive)'. Definition
  # values: - In `<unknown-file>': 80") is on stderr only — not data.
  m = lib.evalModules {
    modules = [
      {
        options.port = lib.mkOption {
          type = lib.types.ints.between 1024 65535;
          default = 8080;
        };
      }
      {
        port = 80;
      }
    ];
  };

  # tryEval: captures the throw but cannot recover the message as a value.
  # success = false proves nixpkgs rejected port = 80; the name/bound are
  # gone — callers cannot pattern-match on them or display them structurally.
  probe = builtins.tryEval m.config.port;

in
{
  # false — nixpkgs rejected port=80, but the blame is a lost string
  success = probe.success;
  # The blame string that WAS thrown (reconstructed from the nixpkgs
  # source; tryEval cannot recover it as a value — illustrative only):
  blame-is-thrown-string = "A definition for option `port' is not of type `integer between 1024 and 65535 (both inclusive)'. Definition values: [80]";
  # Contrast: dzm left carries { why = \"refined\"; name = \"Port\"; got = 80 }
  # — the TYPE NAME is data, selectable, loggable, localizable.
}
