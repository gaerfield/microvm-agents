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
  names = builtins.attrNames instances;
  identityAssignment = name:
    let path = instances.${name}.sshIdentityPath or "";
    in if lib.hasPrefix "~/" path then
      ''sshIdentityPath="$HOME/"${lib.escapeShellArg (lib.removePrefix "~/" path)};''
    else
      ''sshIdentityPath=${lib.escapeShellArg path};'';
  selectVm = { withPort ? false, withService ? false, withIdentity ? false }: ''
    if [ "$#" -ne 1 ]; then
      echo "Usage: $(basename "$0") <instance-name>" >&2
      exit 2
    fi

    vmName="$1"
    case "$vmName" in
      ${lib.concatMapStringsSep "\n" (name: ''
        ${lib.escapeShellArg name}) :; ${lib.optionalString withPort "sshPort=${toString instances.${name}.sshPort};"} ${lib.optionalString withService "serviceName=${lib.escapeShellArg "microvm-${name}"};"} ${lib.optionalString withIdentity (identityAssignment name)} ;;
      '') names}
      *) echo "Unknown VM: $vmName" >&2; exit 2 ;;
    esac
  '';
  command = name: runtimeInputs: text: pkgs.writeShellApplication {
    inherit name runtimeInputs text;
  };
  commands = [
    (command "vm-start" [ pkgs.nix pkgs.systemd ] ''
      ${selectVm { withService = true; }}
      # Run from the private flake checkout, not a read-only Nix store snapshot.
      systemctl --user reset-failed "$serviceName" 2>/dev/null || true
      systemd-run --user \
        --unit="$serviceName" \
        --same-dir \
        nix run ".#$vmName"
    '')
    (command "vm-status" [ pkgs.systemd ] ''
      ${selectVm { withService = true; }}
      systemctl --user status "$serviceName"
    '')
    (command "vm-logs" [ pkgs.systemd ] ''
      ${selectVm { withService = true; }}
      journalctl --user -u "$serviceName" -f
    '')
    (command "vm-stop" [ pkgs.socat ] ''
      ${selectVm { }}
      socket="/tmp/$vmName-qmp.sock"

      if [ ! -S "$socket" ]; then
        echo "QMP socket not found: $socket" >&2
        exit 1
      fi

      {
        echo '{"execute":"qmp_capabilities"}'
        echo '{"execute":"system_powerdown"}'
      } | socat - UNIX-CONNECT:"$socket"
    '')
    (command "vm-ssh" [ pkgs.openssh ] ''
      ${selectVm { withPort = true; withIdentity = true; }}
      sshArgs=()
      if [ -n "$sshIdentityPath" ]; then
        sshArgs=(-i "$sshIdentityPath" -o IdentitiesOnly=yes)
      fi
      ssh "''${sshArgs[@]}" -p "$sshPort" agent@127.0.0.1
    '')
  ];
in
{
  nixosConfigurations = lib.mapAttrs
    (name: args: mkAgentVM ((removeAttrs args [ "sshIdentityPath" ]) // { inherit name; }))
    instances;

  packages.${system} = lib.mapAttrs
    (name: _: self.nixosConfigurations.${name}.config.microvm.declaredRunner)
    instances;

  devShells.${system}.default = pkgs.mkShell {
    packages = commands;
  };
}