{ nixpkgs, microvm, system ? "x86_64-linux" }:

{ name
, workspace
, sshPort
, memory ? 8192
, vcpu ? 4
, authorizedKeys ? [ ]
}:

let
  lib = nixpkgs.lib;
  # A locally administered unicast MAC derived from the full instance name.
  hash = builtins.hashString "sha256" name;
  mac = "02:${builtins.substring 0 2 hash}:${builtins.substring 2 2 hash}:${builtins.substring 4 2 hash}:${builtins.substring 6 2 hash}:${builtins.substring 8 2 hash}";
in
assert lib.assertMsg (builtins.match "[a-z]([a-z0-9-]*[a-z0-9])?" name != null && builtins.stringLength name <= 63)
  "mkAgentVM: name must be a hostname (lowercase letters, digits and hyphens, at most 63 characters)";
assert lib.assertMsg (builtins.match "/.*" workspace != null)
  "mkAgentVM: workspace must be an absolute host path";
assert lib.assertMsg (sshPort >= 1 && sshPort <= 65535)
  "mkAgentVM: sshPort must be between 1 and 65535";
assert lib.assertMsg (memory > 0 && vcpu > 0)
  "mkAgentVM: memory and vcpu must be positive";
lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit name workspace sshPort memory vcpu mac authorizedKeys;
  };
  modules = [
    microvm.nixosModules.microvm
    ../modules/base.nix
    ../modules/agent.nix
    ../modules/podman.nix
  ];
}