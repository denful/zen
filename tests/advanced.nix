zen:
let
  inherit (zen) bend ned fx;

in
{
  advanced = {

    # --- zen.merge.conflict + condition handlers (zen.resolve.*) ---

    test-conflict-use-first = {
      expr = zen.run {
        lens = {
          x = zen.opt zen.merge.conflict zen.types.int;
        };
        defs = [
          (zen.defP 50 { x = 1; })
          (zen.defP 100 { x = 2; })
        ];
        handlers = {
          condition = zen.resolve.useFirst;
        };
      };
      expected = bend.right { x = 1; };
    };

    test-conflict-use-last = {
      expr = zen.run {
        lens = {
          x = zen.opt zen.merge.conflict zen.types.int;
        };
        defs = [
          (zen.defP 50 { x = 1; })
          (zen.defP 100 { x = 2; })
        ];
        handlers = {
          condition = zen.resolve.useLast;
        };
      };
      expected = bend.right { x = 2; };
    };

    test-conflict-reject = {
      expr =
        let
          r = zen.run {
            lens = {
              x = zen.opt zen.merge.conflict zen.types.int;
            };
            defs = [
              (zen.defP 50 { x = 1; })
              (zen.defP 100 { x = 2; })
            ];
            handlers = {
              condition = zen.resolve.reject;
            };
          };
        in
        r ? left && r.left.x ? left && r.left.x.left.why == "conflict";
      expected = true;
    };

    test-conflict-no-handler-is-error = {
      expr =
        let
          r = zen.run {
            lens = {
              x = zen.opt zen.merge.conflict zen.types.int;
            };
            defs = [
              (zen.defP 50 { x = 1; })
              (zen.defP 100 { x = 2; })
            ];
          };
        in
        r ? left && r.left.x ? left && r.left.x.left.why == "negotiating";
      expected = true;
    };

    test-conflict-single-def-right = {
      expr = zen.run {
        lens = {
          n = zen.opt zen.merge.conflict zen.types.int;
        };
        defs = [ (zen.def { n = 42; }) ];
        handlers = {
          condition = zen.resolve.reject;
        };
      };
      expected = bend.right { n = 42; };
    };

    test-conflict-empty-required = {
      expr =
        let
          r = zen.run {
            lens = {
              n = zen.opt zen.merge.conflict zen.types.int;
            };
            defs = [ ];
            handlers = {
              condition = zen.resolve.useFirst;
            };
          };
        in
        r ? left && r.left.n ? left;
      expected = true;
    };

    test-conflict-custom-handler = {
      # Custom handler: always use a fixed fallback value
      expr = zen.run {
        lens = {
          x = zen.opt zen.merge.conflict zen.types.int;
        };
        defs = [
          (zen.def { x = 1; })
          (zen.def { x = 2; })
        ];
        handlers = {
          condition =
            { param, state }:
            {
              resume = {
                restart = "use-value";
                value = bend.right 99;
              };
              inherit state;
            };
        };
      };
      expected = bend.right { x = 99; };
    };

    # --- zen.provide + zen.request ---

    test-provide-request-injects-value = {
      expr = zen.run [
        { options.conn = zen.types.str; }
        (zen.provide { dbUrl = "postgres://localhost/mydb"; } (
          zen.request {
            conn = (
              { dbUrl }:
              {
                value = dbUrl;
                file = "t";
                prio = 100;
              }
            );
          }
        ))
      ];
      expected = bend.right { conn = "postgres://localhost/mydb"; };
    };

    test-provide-multiple-bindings = {
      expr = zen.run [
        {
          options.host = zen.types.str;
          options.port = zen.types.int;
        }
        (zen.provide
          {
            dbHost = "localhost";
            dbPort = 5432;
          }
          (_: {
            host = ned.st (
              { dbHost }:
              {
                value = dbHost;
                file = "t";
                prio = 100;
              }
            );
            port = ned.st (
              { dbPort }:
              {
                value = dbPort;
                file = "t";
                prio = 100;
              }
            );
          })
        )
      ];
      expected = bend.right {
        host = "localhost";
        port = 5432;
      };
    };

    # --- zen.reconcile ---

    test-reconcile-assigns-sequential-ports = {
      expr =
        let
          claims = ned.st.fromList [
            { service = "web"; }
            { service = "db"; }
            { service = "cache"; }
          ];
          portD = zen.reconcile 8000 (
            port: claim: {
              state = port + 1;
              result = {
                service = claim.service;
                port = port;
              };
            }
          );
        in
        (portD claims).toList;
      expected = [
        {
          port = 8000;
          service = "web";
        }
        {
          port = 8001;
          service = "db";
        }
        {
          port = 8002;
          service = "cache";
        }
      ];
    };

    test-reconcile-empty-stream = {
      expr =
        (zen.reconcile 8000 (port: _: {
          state = port + 1;
          result = {
            port = port;
          };
        }) ned.st).toList;
      expected = [ ];
    };

    # --- zen.satisfy ---

    test-proof-int-valid = {
      expr = (zen.satisfy fx.types.Int).get 42;
      expected = bend.right 42;
    };

    test-proof-int-invalid = {
      expr =
        let
          r = (zen.satisfy fx.types.Int).get "not-an-int";
        in
        r ? left;
      expected = true;
    };

    test-proof-str-valid = {
      expr = (zen.satisfy fx.types.String).get "hello";
      expected = bend.right "hello";
    };

    test-proof-bool-valid = {
      expr = (zen.satisfy fx.types.Bool).get true;
      expected = bend.right true;
    };

    test-proof-listOf-valid = {
      expr = (zen.satisfy (fx.types.ListOf fx.types.Int)).get [
        1
        2
        3
      ];
      expected = bend.right [
        1
        2
        3
      ];
    };

    test-proof-listOf-invalid = {
      expr =
        let
          r = (zen.satisfy (fx.types.ListOf fx.types.Int)).get [
            1
            "bad"
            3
          ];
        in
        r ? left;
      expected = true;
    };

    test-proof-in-schema = {
      expr = zen.run [
        { options.port = zen.withDefault 8080 (zen.opt zen.merge.unique (zen.satisfy fx.types.Int)); }
        (zen.def { port = 9000; })
      ];
      expected = bend.right { port = 9000; };
    };

    test-satisfy-pred-valid = {
      expr = (zen.satisfy builtins.isInt).get 42;
      expected = bend.right 42;
    };

    test-satisfy-pred-invalid = {
      expr =
        let
          r = (zen.satisfy builtins.isInt).get "nope";
        in
        r ? left;
      expected = true;
    };

    # --- zen.sub: nested cycle with own fixpoint ---

    test-sub-own-fixpoint = {
      expr = zen.run [
        { options.db = zen.types.sub; }
        (zen.sub {
          db = [
            { options.host = zen.withDefault "localhost" zen.types.str; }
            { options.port = zen.withDefault 5432 zen.types.port; }
            { options.connStr = zen.types.str; }
            # inner fixpoint: srcs are Either (zen.sub uses zen.cycle directly)
            (srcs: {
              config.connStr = "${srcs.host.right or "localhost"}:${builtins.toString (srcs.port.right or 5432)}";
            })
          ];
        })
      ];
      expected = bend.right {
        db = {
          host = "localhost";
          port = 5432;
          connStr = "localhost:5432";
        };
      };
    };

    test-sub-field-overrides = {
      expr = zen.run [
        { options.db = zen.types.sub; }
        (zen.sub {
          db = [
            {
              options.host = zen.withDefault "localhost" zen.types.str;
              config.host = "db.internal";
            }
            {
              options.port = zen.withDefault 5432 zen.types.port;
              config.port = 6543;
            }
          ];
        })
      ];
      expected = bend.right {
        db = {
          host = "db.internal";
          port = 6543;
        };
      };
    };

    test-sub-error-propagates = {
      expr =
        let
          r = zen.run [
            { options.db = zen.types.sub; }
            (zen.sub {
              db = {
                lens = {
                  port = zen.types.port;
                };
                defs = [ ];
              };
            })
          ];
        in
        r ? left;
      expected = true;
    };

    # inter-module: outer module reads merged db config (plain value via fromMods)
    test-inter-module-via-fixpoint = {
      expr = zen.run [
        { options.db = zen.types.sub; }
        { options.webAddr = zen.types.str; }
        (zen.sub {
          db = [
            { options.host = zen.withDefault "localhost" zen.types.str; }
            { options.port = zen.withDefault 5432 zen.types.port; }
            { options.connStr = zen.types.str; }
            (srcs: {
              config.connStr = "${srcs.host.right or "localhost"}:${builtins.toString (srcs.port.right or 5432)}";
            })
          ];
        })
        # outer module receives plain cfg (fromMods path)
        (cfg: { config.webAddr = "http://${cfg.db.connStr or "localhost:5432"}"; })
      ];
      expected = bend.right {
        db = {
          host = "localhost";
          port = 5432;
          connStr = "localhost:5432";
        };
        webAddr = "http://localhost:5432";
      };
    };

    test-sub-context-reads-outer = {
      expr = zen.run [
        {
          options.env = zen.withDefault "prod" zen.types.str;
          config.env = "dev";
        }
        { options.db = zen.types.sub; }
        (zen.sub {
          db = {
            lens = {
              port = zen.withDefault 5432 zen.types.port;
            };
            context = outerSrcs: { appEnv = (builtins.head outerSrcs.env.toList).right or "prod"; };
            defs = [
              (zen.request {
                port = (
                  { appEnv }:
                  {
                    value = if appEnv == "dev" then 5433 else 5432;
                    file = "t";
                    prio = 100;
                  }
                );
              })
            ];
          };
        })
      ];
      expected = bend.right {
        env = "dev";
        db = {
          port = 5433;
        };
      };
    };

    # --- zen.run check: whole-system validation ---

    test-check-pass = {
      expr = zen.run {
        lens = {
          port = zen.withDefault 8080 zen.types.port;
        };
        defs = [ (zen.def { port = 9000; }) ];
        check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
      };
      expected = bend.right { port = 9000; };
    };

    test-check-fail-cross-field = {
      expr =
        let
          r = zen.run {
            lens = {
              protocol = zen.types.str;
              port = zen.types.port;
            };
            defs = [
              (zen.def { protocol = "tcp"; })
              (zen.def { port = 80; })
            ];
            check = bend.ensure (
              cfg: !(cfg.protocol == "tcp" && cfg.port < 1024)
            ) "tcp:port<1024" bend.identity;
          };
        in
        r ? left;
      expected = true;
    };

    test-check-composed-pipe = {
      expr = zen.run {
        lens = {
          x = zen.types.int;
        };
        defs = [ (zen.def { x = 5; }) ];
        check = bend.pipe [
          (bend.ensure (cfg: cfg.x > 0) "positive" bend.identity)
          (bend.ensure (cfg: cfg.x < 10) "lt-10" bend.identity)
        ];
      };
      expected = bend.right { x = 5; };
    };

    test-sub-check-inner = {
      expr =
        let
          r = zen.run [
            { options.db = zen.types.sub; }
            (zen.sub {
              db = {
                lens = {
                  port = zen.withDefault 5432 zen.types.port;
                };
                defs = [ (zen.def { port = 80; }) ];
                check = bend.ensure (cfg: cfg.port > 1024) "port>1024" bend.identity;
              };
            })
          ];
        in
        r ? left;
      expected = true;
    };

    test-sub-nested-nested = {
      expr = zen.run [
        { options.app = zen.types.sub; }
        (zen.sub {
          app = {
            lens = {
              name = zen.withDefault "myapp" zen.types.str;
              db = zen.types.sub;
            };
            defs = [
              (zen.sub {
                db = {
                  lens = {
                    port = zen.withDefault 5432 zen.types.port;
                  };
                  defs = [ (zen.def { port = 5432; }) ];
                };
              })
            ];
          };
        })
      ];
      expected = bend.right {
        app = {
          name = "myapp";
          db = {
            port = 5432;
          };
        };
      };
    };

    # --- named channel inter-module communication (streams for comms — tenet 14) ---

    test-named-channel-inter-module = {
      expr =
        let
          portMod = _: {
            port = 8080;
            portOut = ned.st 8080;
          };
          maxConnMod = sources: {
            maxConn = sources.portOut.map (p: {
              value = p * 10;
              file = "t";
              prio = 100;
            });
          };
        in
        zen.run {
          lens = {
            port = zen.types.int;
            maxConn = zen.types.int;
          };
          defs = [
            portMod
            maxConnMod
          ];
          drivers = {
            portOut = x: x;
          };
        };
      expected = bend.right {
        port = 8080;
        maxConn = 80800;
      };
    };

  };
}
