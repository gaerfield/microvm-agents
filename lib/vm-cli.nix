{ pkgs, lib, instances }:

let
  names = builtins.attrNames instances;
  identityAssignment = name:
    let path = instances.${name}.sshIdentityPath or "";
    in if lib.hasPrefix "~/" path then
      ''sshIdentityPath="$HOME/"${lib.escapeShellArg (lib.removePrefix "~/" path)};''
    else
      ''sshIdentityPath=${lib.escapeShellArg path};'';
  actions = [ "start" "stop" "status" "logs" "ssh" ];
  vmScript = pkgs.writeShellApplication {
    name = "vm";
    runtimeInputs = [ pkgs.nix pkgs.systemd pkgs.socat pkgs.openssh ];
    text = ''
      usage() {
        echo "Usage: vm {${lib.concatStringsSep "|" actions}} <instance-name>" >&2
        exit 2
      }

      if [ "$#" -ne 2 ]; then
        usage
      fi

      action="$1"
      vmName="$2"
      case "$action" in
        ${lib.concatStringsSep "|" actions}) ;;
        *) usage ;;
      esac

      case "$vmName" in
        ${lib.concatMapStringsSep "\n" (name: ''
          ${lib.escapeShellArg name}) sshPort=${toString instances.${name}.sshPort}; ${identityAssignment name} ;;
        '') names}
        *) echo "Unknown VM: $vmName" >&2; exit 2 ;;
      esac

      serviceName="microvm-$vmName"
      case "$action" in
        start)
          # Run from the private flake checkout, not a read-only Nix store snapshot.
          systemctl --user reset-failed "$serviceName" 2>/dev/null || true
          systemd-run --user \
            --unit="$serviceName" \
            --same-dir \
            nix run ".#$vmName"
          ;;
        status)
          systemctl --user status "$serviceName"
          ;;
        logs)
          journalctl --user -u "$serviceName" -f
          ;;
        stop)
          socket="/tmp/$vmName-qmp.sock"
          if [ ! -S "$socket" ]; then
            echo "QMP socket not found: $socket" >&2
            exit 1
          fi
          {
            echo '{"execute":"qmp_capabilities"}'
            echo '{"execute":"system_powerdown"}'
          } | socat - UNIX-CONNECT:"$socket"
          ;;
        ssh)
          sshArgs=()
          if [ -n "$sshIdentityPath" ]; then
            sshArgs=(-i "$sshIdentityPath" -o IdentitiesOnly=yes)
          fi
          ssh "''${sshArgs[@]}" -p "$sshPort" agent@127.0.0.1
          ;;
      esac
    '';
  };
  fishCompletion = pkgs.writeTextFile {
    name = "vm-fish-completion";
    destination = "/share/fish/vendor_completions.d/vm.fish";
    text = ''
      complete -c vm -f
      complete -c vm -n 'test (count (commandline -opc)) -eq 1' -a '${lib.concatStringsSep " " actions}'
      complete -c vm -n 'test (count (commandline -opc)) -eq 2; and contains -- (commandline -opc)[2] ${lib.concatStringsSep " " actions}' -a '${lib.concatStringsSep " " names}'
    '';
  };
in
pkgs.symlinkJoin {
  name = "vm-cli";
  paths = [ vmScript fishCompletion ];
}