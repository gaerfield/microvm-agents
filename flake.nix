{
  description = "NixOS in MicroVMs";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs.nixpkgs.url = "nixpkgs";

  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, microvm, ... }:
    let
      system = "x86_64-linux";
      mkAgentVM = import ./lib/mkAgentVM.nix {
        inherit nixpkgs microvm system;
      };
    in
    {
      lib.mkAgentVM = mkAgentVM;
      lib.mkInstances = import ./lib/mkInstances.nix {
        inherit nixpkgs mkAgentVM system;
      };

      templates.default = {
        path = ./templates/default;
        description = "Private microvm-agents instance project";
      };
    };
}
