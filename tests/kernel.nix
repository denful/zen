zen:
let
  inherit (zen) bend ned opt;
  inherit (zen.merge) unique;

  intL = opt unique bend.int;
  strL = opt unique bend.str;

in
{
  kernel = {

    # T1: single option → right
    test-single-def-right = {
      expr = zen.run [
        {
          options.port = intL;
          config.port = 8080;
        }
      ];
      expected = bend.right { port = 8080; };
    };

    # T6: multiple options → right
    test-multi-option-right = {
      expr = zen.run [
        {
          options = {
            port = intL;
            host = strL;
          };
          config = {
            port = 8080;
            host = "localhost";
          };
        }
      ];
      expected = bend.right {
        port = 8080;
        host = "localhost";
      };
    };

    # T2: conflict — 2 modules set same option → left
    test-conflict-left = {
      expr =
        let
          result = zen.run [
            {
              options.port = intL;
              config.port = 8080;
            }
            { config.port = 9000; }
          ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T3: missing option — no def → left
    test-missing-left = {
      expr =
        let
          result = zen.run [ { options.port = intL; } ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T4: type error — string where int expected → left
    test-type-error-left = {
      expr =
        let
          result = zen.run [
            {
              options.port = intL;
              config.port = "not-an-int";
            }
          ];
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T5: fixpoint — hostMod reads cfg.port (plain value, no .right needed)
    test-fixpoint = {
      expr =
        let
          hostMod = cfg: {
            options.host = strL;
            config.host = "localhost:${toString (cfg.port or 80)}";
          };
        in
        zen.run [
          {
            options.port = intL;
            config.port = 8080;
          }
          hostMod
        ];
      expected = bend.right {
        port = 8080;
        host = "localhost:8080";
      };
    };

    # T7: partial errors — port conflict, host ok → left with mixed results
    test-partial-errors = {
      expr =
        let
          result = zen.run [
            {
              options = {
                port = intL;
                host = strL;
              };
              config.port = 8080;
            }
            { config.port = 9000; }
            { config.host = "localhost"; }
          ];
        in
        result ? left && result.left.port ? left && result.left.host ? right;
      expected = true;
    };

  };
}
