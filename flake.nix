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

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      mkAgentVM = import ./lib/mkAgentVM.nix {
        inherit nixpkgs microvm system;
      };
      lib = nixpkgs.lib;
      instanceFiles = lib.filterAttrs
        (file: type: type == "regular" && lib.hasSuffix ".nix" file)
        (builtins.readDir ./instances);
      instances = lib.mapAttrs'
        (file: _: lib.nameValuePair
          (lib.removeSuffix ".nix" file)
          (import (./instances + "/${file}")))
        instanceFiles;
      instanceConfigurations = nixpkgs.lib.mapAttrs
        (name: args: mkAgentVM (args // { inherit name; }))
        instances;
    in assert lib.assertMsg (!(builtins.hasAttr "my-microvm" instances))
      "instances/my-microvm.nix would shadow the reference VM";
    {
      lib.mkAgentVM = mkAgentVM;

      packages.${system} =
        nixpkgs.lib.mapAttrs
          (name: _: self.nixosConfigurations.${name}.config.microvm.declaredRunner)
          instances
        // {
          default = self.packages.${system}.my-microvm;
          my-microvm = self.nixosConfigurations.my-microvm.config.microvm.declaredRunner;
        };

      nixosConfigurations = instanceConfigurations // {
        my-microvm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            microvm.nixosModules.microvm
            ./microvm.nix
          ];
        };
      };
    };
}
