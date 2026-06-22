zen:
let
  inherit (zen) bend;
  b = bend;

in
{
  dx = {

    # --- zen.merge.unique ---

    test-m-unique-single = {
      expr = zen.run [
        {
          options.x = zen.opt zen.merge.unique zen.types.int;
          config.x = 42;
        }
      ];
      expected = bend.right { x = 42; };
    };

    test-m-unique-conflict = {
      expr =
        let
          r = zen.run [
            { options.x = zen.opt zen.merge.unique zen.types.int; }
            (zen.def { x = 1; })
            (zen.def { x = 2; })
          ];
        in
        zen.test.isConflict r "x";
      expected = true;
    };

    test-m-unique-empty = {
      expr =
        let
          r = zen.run [ { options.x = zen.opt zen.merge.unique zen.types.int; } ];
        in
        zen.test.isRequired r "x";
      expected = true;
    };

    # --- zen.merge.first / last ---

    test-m-first-picks-low-prio = {
      expr = zen.run [
        { options.x = zen.opt zen.merge.first zen.types.int; }
        (zen.defP 50 { x = 1; })
        (zen.defP 100 { x = 2; })
      ];
      expected = bend.right { x = 1; };
    };

    # R3 NOTE: priority is now a FILTER applied BEFORE the merge strategy (spec
    # §6). With defs at prio 50 and 100, ONLY the prio-50 def survives the filter,
    # so the `last` strategy sees a single survivor ⇒ x = 1. The pre-R3 expectation
    # (last picks the prio-100 def) relied on the strategy doing its own cross-prio
    # selection, which R3's filter subsumes: the numerically-lower priority wins
    # outright regardless of strategy. (See r3.test_R3_priority_is_filter for the
    # load-bearing G1 proof that sub-top-priority defs are DROPPED.)
    test-m-last-filtered-to-high-prio = {
      expr = zen.run [
        { options.x = zen.opt zen.merge.last zen.types.int; }
        (zen.defP 50 { x = 1; })
        (zen.defP 100 { x = 2; })
      ];
      expected = bend.right { x = 1; };
    };

    # --- zen.merge.concat ---

    test-m-concat-empty = {
      expr = zen.run [ { options.xs = zen.types.listOf zen.types.int; } ];
      expected = bend.right { xs = [ ]; };
    };

    test-m-concat-merges = {
      expr = zen.run [
        {
          options.xs = zen.types.listOf zen.types.int;
          config.xs = [
            1
            2
          ];
        }
        {
          config.xs = [
            3
            4
          ];
        }
      ];
      expected = bend.right {
        xs = [
          1
          2
          3
          4
        ];
      };
    };

    # --- zen.merge.attrs ---

    test-m-attrs-merges = {
      expr = zen.run [
        {
          options.m = zen.types.attrsOf zen.types.str;
          config.m = {
            a = "x";
          };
        }
        {
          config.m = {
            b = "y";
          };
        }
      ];
      expected = bend.right {
        m = {
          a = "x";
          b = "y";
        };
      };
    };

    # --- zen.t primitives ---

    test-t-int = {
      expr = zen.run [
        {
          options.n = zen.types.int;
          config.n = 99;
        }
      ];
      expected = bend.right { n = 99; };
    };

    test-t-str = {
      expr = zen.run [
        {
          options.s = zen.types.str;
          config.s = "hello";
        }
      ];
      expected = bend.right { s = "hello"; };
    };

    test-t-bool = {
      expr = zen.run [
        {
          options.b = zen.types.bool;
          config.b = true;
        }
      ];
      expected = bend.right { b = true; };
    };

    test-t-int-type-error = {
      expr =
        let
          r = zen.run [
            {
              options.n = zen.types.int;
              config.n = "oops";
            }
          ];
        in
        zen.test.fieldError r "n";
      expected = true;
    };

    # --- zen.t port ---

    test-t-port-min = {
      expr = zen.run [
        {
          options.p = zen.types.port;
          config.p = 0;
        }
      ];
      expected = bend.right { p = 0; };
    };

    test-t-port-max = {
      expr = zen.run [
        {
          options.p = zen.types.port;
          config.p = 65535;
        }
      ];
      expected = bend.right { p = 65535; };
    };

    test-t-port-over = {
      expr =
        let
          r = zen.run [
            {
              options.p = zen.types.port;
              config.p = 65536;
            }
          ];
        in
        zen.test.fieldError r "p";
      expected = true;
    };

    # --- zen.types.listOf ---

    test-t-listOf-concat = {
      expr = zen.run [
        {
          options.tags = zen.types.listOf b.str;
          config.tags = [
            "a"
            "b"
          ];
        }
        { config.tags = [ "c" ]; }
      ];
      expected = bend.right {
        tags = [
          "a"
          "b"
          "c"
        ];
      };
    };

    test-t-listOf-empty = {
      expr = zen.run [ { options.tags = zen.types.listOf b.str; } ];
      expected = bend.right { tags = [ ]; };
    };

    test-t-listOf-type-error = {
      expr =
        let
          r = zen.run [
            {
              options.tags = zen.types.listOf b.int;
              config.tags = [ "bad" ];
            }
          ];
        in
        zen.test.fieldError r "tags";
      expected = true;
    };

    # --- zen.types.attrsOf ---

    test-t-attrsOf-merges = {
      expr = zen.run [
        {
          options.env = zen.types.attrsOf b.str;
          config.env = {
            A = "1";
          };
        }
        {
          config.env = {
            B = "2";
          };
        }
      ];
      expected = bend.right {
        env = {
          A = "1";
          B = "2";
        };
      };
    };

    # --- zen.types.nullOr ---

    test-t-nullOr-null = {
      expr = zen.run [
        {
          options.x = zen.types.nullOr b.int;
          config.x = null;
        }
      ];
      expected = bend.right { x = null; };
    };

    test-t-nullOr-value = {
      expr = zen.run [
        {
          options.x = zen.types.nullOr b.int;
          config.x = 7;
        }
      ];
      expected = bend.right { x = 7; };
    };

    test-t-nullOr-type-error = {
      expr =
        let
          r = zen.run [
            {
              options.x = zen.types.nullOr b.int;
              config.x = "bad";
            }
          ];
        in
        zen.test.fieldError r "x";
      expected = true;
    };

    # --- zen.withDefault ---

    test-withDefault-empty = {
      expr = zen.run [ { options.p = zen.withDefault 8080 zen.types.int; } ];
      expected = bend.right { p = 8080; };
    };

    test-withDefault-overridden = {
      expr = zen.run [
        {
          options.p = zen.withDefault 8080 zen.types.int;
          config.p = 9000;
        }
      ];
      expected = bend.right { p = 9000; };
    };

    test-withDefault-list-empty = {
      expr = zen.run [ { options.xs = zen.withDefault [ 1 2 ] (zen.types.listOf b.int); } ];
      expected = bend.right {
        xs = [
          1
          2
        ];
      };
    };

    # --- zen.types.submod ---

    test-submod-valid = {
      expr = zen.run [
        {
          options.db = zen.types.submod {
            host = zen.types.str;
            port = zen.types.int;
          };
          config.db = {
            host = "localhost";
            port = 5432;
          };
        }
      ];
      expected = bend.right {
        db = {
          host = "localhost";
          port = 5432;
        };
      };
    };

    test-submod-type-error = {
      expr =
        let
          r = zen.run [
            {
              options.db = zen.types.submod {
                host = zen.types.str;
                port = zen.types.int;
              };
              config.db = {
                host = "localhost";
                port = "bad";
              };
            }
          ];
        in
        zen.test.fieldError r "db";
      expected = true;
    };

    test-submod-not-attrset = {
      expr =
        let
          r = zen.run [
            {
              options.db = zen.types.submod { host = zen.types.str; };
              config.db = 42;
            }
          ];
        in
        zen.test.fieldError r "db";
      expected = true;
    };

    test-submod-with-default = {
      expr = zen.run [
        {
          options.db =
            zen.withDefault
              {
                host = "localhost";
                port = 5432;
              }
              (
                zen.types.submod {
                  host = zen.types.str;
                  port = zen.types.int;
                }
              );
        }
      ];
      expected = bend.right {
        db = {
          host = "localhost";
          port = 5432;
        };
      };
    };

    # --- zen.types.* inner-type lenses ---

    test-ti-listOf-str = {
      expr = zen.run [
        {
          options.tags = zen.types.listOf zen.types.str;
          config.tags = [
            "a"
            "b"
          ];
        }
        { config.tags = [ "c" ]; }
      ];
      expected = bend.right {
        tags = [
          "a"
          "b"
          "c"
        ];
      };
    };

    test-ti-listOf-port = {
      expr = zen.run [
        {
          options.ports = zen.types.listOf zen.types.port;
          config.ports = [
            80
            443
            8080
          ];
        }
      ];
      expected = bend.right {
        ports = [
          80
          443
          8080
        ];
      };
    };

    test-ti-listOf-port-error = {
      expr =
        let
          r = zen.run [
            {
              options.ports = zen.types.listOf zen.types.port;
              config.ports = [
                80
                99999
              ];
            }
          ];
        in
        zen.test.fieldError r "ports";
      expected = true;
    };

    # --- zen.def / zen.defP ---

    test-def-basic = {
      expr = zen.run [
        { options.n = zen.types.int; }
        (zen.def { n = 42; })
      ];
      expected = bend.right { n = 42; };
    };

    test-def-replaces-mkDef = {
      expr = zen.run [
        {
          options.host = zen.types.str;
          options.port = zen.types.int;
        }
        (zen.def { host = "localhost"; })
        (zen.def { port = 8080; })
      ];
      expected = bend.right {
        host = "localhost";
        port = 8080;
      };
    };

    test-defP-force-wins = {
      expr = zen.run [
        { options.x = zen.opt zen.merge.first zen.types.int; }
        (zen.defP 50 { x = 1; })
        (zen.defP 100 { x = 2; })
      ];
      expected = bend.right { x = 1; };
    };

    test-defP-default-loses = {
      expr = zen.run [
        { options.x = zen.opt zen.merge.first zen.types.int; }
        (zen.defP 1000 { x = 99; })
        (zen.defP 100 { x = 42; })
      ];
      expected = bend.right { x = 42; };
    };

    # --- zen.types.attrsSubmod ---

    test-attrsSubmod-multi-def = {
      expr = zen.run [
        {
          options.db = zen.types.attrsSubmod {
            host = zen.types.str;
            port = zen.types.int;
          };
        }
        (zen.def {
          db = {
            host = "localhost";
          };
        })
        (zen.def {
          db = {
            port = 5432;
          };
        })
      ];
      expected = bend.right {
        db = {
          host = "localhost";
          port = 5432;
        };
      };
    };

    test-attrsSubmod-single-def = {
      expr = zen.run [
        { options.db = zen.types.attrsSubmod { host = zen.types.str; }; }
        (zen.def {
          db = {
            host = "db.example.com";
          };
        })
      ];
      expected = bend.right {
        db = {
          host = "db.example.com";
        };
      };
    };

    test-attrsSubmod-type-error = {
      expr =
        let
          r = zen.run [
            {
              options.db = zen.types.attrsSubmod {
                host = zen.types.str;
                port = zen.types.int;
              };
            }
            (zen.def {
              db = {
                host = "localhost";
                port = "bad";
              };
            })
          ];
        in
        zen.test.fieldError r "db";
      expected = true;
    };

    test-attrsSubmod-empty-is-missing = {
      expr =
        let
          r = zen.run [ { options.db = zen.types.attrsSubmod { host = zen.types.str; }; } ];
        in
        zen.test.fieldError r "db";
      expected = true;
    };

    test-attrsSubmod-empty-no-schema = {
      expr = zen.run [ { options.tags = zen.types.attrsSubmod { }; } ];
      expected = bend.right { tags = { }; };
    };

  };
}
