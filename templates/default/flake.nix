{
  description = "Private AI agent MicroVM instances";

  inputs.microvm-agents.url = "github:gaerfield/microvm-agents";
  inputs.nixpkgs.follows = "microvm-agents/nixpkgs";

  outputs = { self, microvm-agents, nixpkgs }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = pkg: (pkg.pname or "") == "github-copilot-cli";
      };
    in microvm-agents.lib.mkInstances {
      inherit self pkgs;
      instancesDir = ./instances;
    };
}