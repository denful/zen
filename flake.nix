{
  inputs = {
    dnzl.url = "github:denful/dnzl";
    dnzl.flake = false;
  };

  outputs = inputs: {
    lib = import ./. { inherit inputs; };
  };
}
