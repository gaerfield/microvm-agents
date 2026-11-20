{ nixpkgs, mkAgentVM, system ? "x86_64-linux" }:

{ self, instancesDir }:

let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};
  files = lib.filterAttrs
    (file: type: type == "regular" && lib.hasSuffix ".nix" file)
    (builtins.readDir instancesDir);
  instances = lib.mapAttrs'
    (file: _: lib.nameValuePair
      (lib.removeSuffix ".nix" file)
      (import (instancesDir + "/${file}")))
    files;
  vmCli = import ./vm-cli.nix { inherit pkgs lib instances; };
in
{
  nixosConfigurations = lib.mapAttrs
    (name: args: mkAgentVM ((removeAttrs args [ "sshIdentityPath" ]) // { inherit name; }))
    instances;

  packages.${system} = lib.mapAttrs
    (name: _: self.nixosConfigurations.${name}.config.microvm.declaredRunner)
    instances;

  devShells.${system}.default = pkgs.mkShell {
    packages = [ vmCli ];
  };
}