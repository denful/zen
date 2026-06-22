let
  zen = import ../. { };
  N = 10000;

  # Faithful nested-submodule type: a package's deps are themselves typed
  # submodules. Composite type-lenses expose `.inner`, so submodOf recurses
  # uniformly through `listOf dep`.
  dep = zen.types.submod {
    name = zen.types.str;
    version = zen.types.str;
  };
  pkg = zen.types.submod {
    name = zen.types.str;
    version = zen.types.str;
    deps = zen.types.listOf dep;
  };

  base = {
    options.packages = zen.withDefault [ ] (zen.types.listOf pkg);
    options.tags = zen.withDefault [ ] (zen.types.listOf zen.types.str);
    options.meta = zen.withDefault { count = 0; } (zen.types.submod { count = zen.types.int; });
    config.meta = {
      count = N;
    };
  };

  stressMods = builtins.genList (
    k:
    let
      i = k + 1;
      s = toString i;
    in
    {
      config.packages = [
        {
          name = "pkg-${s}";
          version = "${s}.0";
          deps = [
            {
              name = "dep-a-${s}";
              version = "1.0";
            }
            {
              name = "dep-b-${s}";
              version = "2.0";
            }
            {
              name = "dep-c-${s}";
              version = "3.0";
            }
            {
              name = "dep-d-${s}";
              version = "4.0";
            }
            {
              name = "dep-e-${s}";
              version = "5.0";
            }
          ];
        }
      ];
      config.tags = [ "tag-${s}" ];
    }
  ) N;

in
(zen.run { modules = [ base ] ++ stressMods; }).right
