zen:
let
  inherit (zen) fx bend ned;
in
{
  smoke = {
    test-works = {
      expr = 20;
      expected = 20;
    };
  };
}
