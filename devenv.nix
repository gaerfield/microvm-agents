{ pkgs, ... }:

let
  directory = builtins.readDir ./instances;
  instanceFiles = builtins.filter
    (file: directory.${file} == "regular"
      && pkgs.lib.hasSuffix ".nix" file)
    (builtins.attrNames directory);
  instanceNames = map (pkgs.lib.removeSuffix ".nix") instanceFiles;
  instanceCases = builtins.concatStringsSep "\n" (map (name: ''
    ${pkgs.lib.escapeShellArg name}) sshPort=${toString (import (./instances + "/${name}.nix")).sshPort}; serviceName=${pkgs.lib.escapeShellArg "microvm-${name}"} ;;
  '') instanceNames);
  selectVm = ''
    if [ "$#" -gt 1 ]; then
      echo "Usage: $(basename "$0") [instance-name]" >&2
      exit 2
    fi

    vmName="''${1:-my-microvm}"
    case "$vmName" in
      my-microvm) sshPort=2222; serviceName=microvm-one ;;
      ${instanceCases}
      *) echo "Unknown VM: $vmName" >&2; exit 2 ;;
    esac
  '';
in
{
  packages = with pkgs; [
    socat
    openssh
  ];

  scripts.vm-start.exec = ''
    ${selectVm}
    systemd-run --user \
      --unit="$serviceName" \
      --same-dir \
      --collect \
      nix run ".#nixosConfigurations.$vmName.config.microvm.declaredRunner"
  '';

  scripts.vm-status.exec = ''
    ${selectVm}
    systemctl --user status "$serviceName"
  '';

  scripts.vm-logs.exec = ''
    ${selectVm}
    journalctl --user -u "$serviceName" -f
  '';

  # Unlike systemctl --user stop, this gives the guest an opportunity to flush filesystems and stop services.
  scripts.vm-stop.exec = ''
    ${selectVm}
    socket="/tmp/$vmName-qmp.sock"

    if [ ! -S "$socket" ]; then
      echo "QMP socket not found: $socket" >&2
      exit 1
    fi

    {
      echo '{"execute":"qmp_capabilities"}'
      echo '{"execute":"system_powerdown"}'
    } | socat - UNIX-CONNECT:"$socket"
  '';

  scripts.vm-ssh.exec = ''
    ${selectVm}
    if [ "$vmName" = my-microvm ]; then
      ssh agent-vm
    else
      ssh -p "$sshPort" agent@127.0.0.1
    fi
  '';
}