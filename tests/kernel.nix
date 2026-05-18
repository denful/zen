zen:
let
  inherit (zen) bend ned;
  inherit (builtins) length head;

  # Lens: unique merge ([Def] → Either value _) + no type check
  anyL = bend.pipe [
    (bend.parse (
      defs:
      if defs == [ ] then
        bend.left { why = "required"; }
      else if length defs == 1 then
        bend.right (head defs).value
      else
        bend.left {
          why = "conflict";
          inherit defs;
        }
    ) bend.identity)
    bend.identity
  ];

  # Lens: unique merge + int type
  intL = bend.pipe [
    (bend.parse (
      defs:
      if defs == [ ] then
        bend.left { why = "required"; }
      else if length defs == 1 then
        bend.right (head defs).value
      else
        bend.left {
          why = "conflict";
          inherit defs;
        }
    ) bend.identity)
    bend.int
  ];

  # Lens: unique merge + str type
  strL = bend.pipe [
    (bend.parse (
      defs:
      if defs == [ ] then
        bend.left { why = "required"; }
      else if length defs == 1 then
        bend.right (head defs).value
      else
        bend.left {
          why = "conflict";
          inherit defs;
        }
    ) bend.identity)
    bend.str
  ];

  mkDef =
    name: value: _srcs:
    ned.st.fromList [
      {
        inherit name value;
        file = "test";
        prio = 100;
      }
    ];

in
{
  kernel = {

    # T1: single def, single option → right
    test-single-def-right = {
      expr = zen.run {
        lens = {
          port = intL;
        };
        defs = [ (mkDef "port" 8080) ];
      };
      expected = bend.right { port = 8080; };
    };

    # T6: multiple options, all present → right
    test-multi-option-right = {
      expr = zen.run {
        lens = {
          port = intL;
          host = strL;
        };
        defs = [
          (mkDef "port" 8080)
          (mkDef "host" "localhost")
        ];
      };
      expected = bend.right {
        port = 8080;
        host = "localhost";
      };
    };

    # T2: conflict — 2 defs for same option → left
    test-conflict-left = {
      expr =
        let
          result = zen.run {
            lens = {
              port = intL;
            };
            defs = [
              (mkDef "port" 8080)
              (mkDef "port" 9000)
            ];
          };
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T3: missing option — no def → left
    test-missing-left = {
      expr =
        let
          result = zen.run {
            lens = {
              port = intL;
            };
            defs = [ ];
          };
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T4: type error — string where int expected → left
    test-type-error-left = {
      expr =
        let
          result = zen.run {
            lens = {
              port = intL;
            };
            defs = [ (mkDef "port" "not-an-int") ];
          };
        in
        result ? left && result.left ? port && result.left.port ? left;
      expected = true;
    };

    # T5: fixpoint — hostDef reads srcs.config.port to derive host value
    test-fixpoint = {
      expr =
        let
          portDef = mkDef "port" 8080;
          hostDef =
            srcs:
            let
              port = if srcs.config.port ? right then srcs.config.port.right else 80;
            in
            ned.st.fromList [
              {
                name = "host";
                value = "localhost:${toString port}";
                file = "test";
                prio = 100;
              }
            ];
        in
        zen.run {
          lens = {
            port = intL;
            host = strL;
          };
          defs = [
            portDef
            hostDef
          ];
        };
      expected = bend.right {
        port = 8080;
        host = "localhost:8080";
      };
    };

    # T7: partial errors — port fails, host passes → left with mixed results
    test-partial-errors = {
      expr =
        let
          result = zen.run {
            lens = {
              port = intL;
              host = strL;
            };
            defs = [
              (mkDef "port" 8080)
              (mkDef "port" 9000)
              (mkDef "host" "localhost")
            ];
          };
        in
        result ? left && result.left.port ? left && result.left.host ? right;
      expected = true;
    };

  };
}
