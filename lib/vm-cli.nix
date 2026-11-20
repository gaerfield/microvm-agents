{ pkgs, lib, instances }:

let
  names = builtins.attrNames instances;
  identityAssignment = name:
    let path = instances.${name}.sshIdentityPath or "";
    in if lib.hasPrefix "~/" path then
      ''sshIdentityPath="$HOME/"${lib.escapeShellArg (lib.removePrefix "~/" path)};''
    else
      ''sshIdentityPath=${lib.escapeShellArg path};'';
  actions = [ "create" "start" "stop" "status" "logs" "ssh" "destroy" "orphaned" ];
  vmScript = pkgs.writeShellApplication {
    name = "vm";
    runtimeInputs = [ pkgs.nix pkgs.systemd pkgs.socat pkgs.openssh pkgs.jq pkgs.coreutils ];
    text = ''
      usage() {
        echo "Usage: vm {start|stop|status|logs|ssh} <instance-name>" >&2
        echo "       vm create <name> --workspace PATH --ssh-port PORT (--identity PRIVATE_KEY | --public-key PUBLIC_KEY_FILE) [--memory MiB] [--vcpu COUNT]" >&2
        echo "       vm destroy <name> [--yes]" >&2
        echo "       vm orphaned" >&2
        exit 2
      }

      [ "$#" -ge 1 ] || usage
      action="$1"
      shift
      dataHome="''${XDG_DATA_HOME:-$HOME/.local/share}"
      case "$dataHome" in
        /*) ;;
        *) echo "XDG_DATA_HOME must be an absolute path: $dataHome" >&2; exit 2 ;;
      esac
      dataRoot="$dataHome/microvm-agents"

      requireFlakeRoot() {
        if [ ! -f ./flake.nix ] || [ ! -d ./instances ]; then
          echo "Run vm $action from the private flake directory (with an instances directory)." >&2
          exit 2
        fi
      }

      nixString() {
        # shellcheck disable=SC2016 -- jq, not the shell, expands $value.
        jq -Rn --arg value "$1" '$value'
      }

      case "$action" in
        create)
          [ "$#" -ge 1 ] || usage
          vmName="$1"
          shift
          requireFlakeRoot
          if [[ ! "$vmName" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?$ ]] || [ "''${#vmName}" -gt 63 ]; then
            echo "Invalid VM name: $vmName" >&2; exit 2
          fi
          workspace="" sshPort="" identity="" publicKeyFile="" memory="" vcpu=""
          while [ "$#" -gt 0 ]; do
            [ "$#" -ge 2 ] || usage
            case "$1" in
              --workspace) workspace="$2" ;;
              --ssh-port) sshPort="$2" ;;
              --identity) identity="$2" ;;
              --public-key) publicKeyFile="$2" ;;
              --memory) memory="$2" ;;
              --vcpu) vcpu="$2" ;;
              *) usage ;;
            esac
            shift 2
          done
          if [[ "$workspace" != /* ]] || [ ! -d "$workspace" ]; then
            echo "Workspace must be an existing absolute directory: $workspace" >&2; exit 2
          fi
          if [[ ! "$sshPort" =~ ^[1-9][0-9]*$ ]] || [ "''${#sshPort}" -gt 5 ] || (( sshPort > 65535 )); then
            echo "SSH port must be between 1 and 65535" >&2; exit 2
          fi
          for number in "$memory" "$vcpu"; do
            if [ -n "$number" ] && [[ ! "$number" =~ ^[1-9][0-9]*$ ]]; then
              echo "Memory and vCPU must be positive integers" >&2; exit 2
            fi
          done
          if [ -n "$identity" ] && [ -n "$publicKeyFile" ]; then
            echo "Choose either --identity or --public-key" >&2; exit 2
          fi
          if [ -n "$identity" ]; then
            if [[ "$identity" != /* ]] || [ ! -f "$identity" ]; then
              echo "Identity must be an existing absolute private key path" >&2; exit 2
            fi
            publicKeyFile="$identity.pub"
          fi
          if [ ! -f "$publicKeyFile" ]; then
            echo "Provide an existing public key file (or an identity with a .pub file)" >&2; exit 2
          fi
          publicKey="$(cat -- "$publicKeyFile")"
          if [[ "$publicKey" == *$'\n'* ]] || ! ssh-keygen -l -f "$publicKeyFile" >/dev/null 2>&1; then
            echo "Invalid SSH public key: $publicKeyFile" >&2; exit 2
          fi
          if [[ "$workspace" == *'$'* || "$identity" == *'$'* || "$publicKey" == *'$'* ]] || [[ "$workspace" =~ [[:cntrl:]] || "$identity" =~ [[:cntrl:]] || "$publicKey" =~ [[:cntrl:]] ]]; then
            echo "Paths and public keys cannot contain dollar signs or control characters in generated Nix" >&2; exit 2
          fi
          ${lib.optionalString (names != [ ]) ''
            case "$sshPort" in
              ${lib.concatMapStringsSep "|" (name: toString instances.${name}.sshPort) names})
                echo "SSH port is already used by another VM: $sshPort" >&2; exit 2 ;;
            esac
          ''}
          configFile="./instances/$vmName.nix"
          stateDir="$dataRoot/$vmName"
          if [ -e "$configFile" ] || [ -L "$configFile" ] || [ -e "$stateDir" ] || [ -L "$stateDir" ]; then
            echo "VM definition or state already exists for $vmName" >&2; exit 1
          fi
          workspaceNix="$(nixString "$workspace")"
          publicKeyNix="$(nixString "$publicKey")"
          if [ -n "$identity" ]; then identityNix="$(nixString "$identity")"; fi
          ( umask 077
            tempFile="$(mktemp "./instances/.$vmName.XXXXXXXX")"
            trap 'rm -f -- "$tempFile"' EXIT
            {
              printf '{\n  workspace = %s;\n' "$workspaceNix"
              printf '  sshPort = %s;\n' "$sshPort"
              printf '  authorizedKeys = [ %s ];\n' "$publicKeyNix"
              if [ -n "$identity" ]; then printf '  sshIdentityPath = %s;\n' "$identityNix"; fi
              if [ -n "$memory" ]; then printf '  memory = %s;\n' "$memory"; fi
              if [ -n "$vcpu" ]; then printf '  vcpu = %s;\n' "$vcpu"; fi
              printf '}\n'
            } > "$tempFile"
            ln -- "$tempFile" "$configFile"
          )
          echo "Created $configFile. Re-enter nix develop to load $vmName; if using Git, track the definition before evaluating the flake."
          ;;
        orphaned)
          [ "$#" -eq 0 ] || usage
          requireFlakeRoot
          if [ -d "$dataRoot" ]; then
            for stateDir in "$dataRoot"/*; do
              if [ ! -d "$stateDir" ] || [ -L "$stateDir" ]; then continue; fi
              name="''${stateDir##*/}"
              if [ ! -f "./instances/$name.nix" ]; then printf '%s\n' "$name"; fi
            done
          fi
          ;;
        destroy)
          [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
          vmName="$1"
          [ "$#" -eq 1 ] || [ "$2" = --yes ] || usage
          requireFlakeRoot
          if [[ ! "$vmName" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?$ ]] || [ "''${#vmName}" -gt 63 ]; then
            echo "Invalid VM name: $vmName" >&2; exit 2
          fi
          configFile="./instances/$vmName.nix"
          stateDir="$dataRoot/$vmName"
          if [ ! -f "$configFile" ] && [ ! -d "$stateDir" ]; then
            echo "No definition or state for VM: $vmName" >&2; exit 2
          fi
          if [ -L "$stateDir" ] || [ -L "$configFile" ] || [ -L "$dataRoot" ]; then
            echo "Refusing to delete symlinked VM paths" >&2; exit 1
          fi
          if [ "$#" -eq 1 ]; then
            read -r -p "Remove definition and ALL VM state for $vmName (worktree untouched)? Type $vmName to confirm: " answer
            if [ "$answer" != "$vmName" ]; then echo "Cancelled" >&2; exit 1; fi
          fi
          serviceName="microvm-$vmName"
          if ! systemctl --user list-units --all --no-legend --no-pager "$serviceName" >/dev/null; then
            echo "Cannot contact user systemd; state preserved" >&2; exit 1
          fi
          serviceState="$(systemctl --user show -p ActiveState --value "$serviceName" 2>/dev/null || echo inactive)"
          case "$serviceState" in
            inactive|failed)
              if [ -S "/tmp/$vmName-qmp.sock" ]; then
                echo "QMP socket still exists; refusing to remove VM state" >&2; exit 1
              fi
              ;;
            active)
              socket="/tmp/$vmName-qmp.sock"
              if [ ! -S "$socket" ]; then
                echo "Running VM has no QMP socket; stop it manually before destroying" >&2; exit 1
              fi
              {
                echo '{"execute":"qmp_capabilities"}'
                echo '{"execute":"system_powerdown"}'
              } | socat - UNIX-CONNECT:"$socket"
              for (( attempt = 0; attempt < 60; attempt++ )); do
                if ! serviceState="$(systemctl --user show -p ActiveState --value "$serviceName")"; then
                  echo "Cannot verify VM shutdown; state preserved" >&2; exit 1
                fi
                case "$serviceState" in inactive|failed) break ;; esac
                sleep 1
              done
              if [ "$serviceState" != inactive ] && [ "$serviceState" != failed ]; then
                echo "VM did not stop; state preserved" >&2; exit 1
              fi
              ;;
            *) echo "VM service is $serviceState; state preserved" >&2; exit 1 ;;
          esac
          if [ -d "$stateDir" ]; then rm -rf -- "''${stateDir:?}"; fi
          if [ -f "$configFile" ]; then rm -- "$configFile"; fi
          echo "Destroyed $vmName (worktree and legacy images untouched). Re-enter nix develop to refresh commands."
          ;;
        start|stop|status|logs|ssh)
          [ "$#" -eq 1 ] || usage
          vmName="$1"
          case "$vmName" in
            ${lib.concatMapStringsSep "\n" (name: ''
              ${lib.escapeShellArg name}) sshPort=${toString instances.${name}.sshPort}; ${identityAssignment name} ;;
            '') names}
            *) echo "Unknown VM: $vmName" >&2; exit 2 ;;
          esac
          serviceName="microvm-$vmName"
          case "$action" in
            start)
              flakeDir="$PWD"
              if [ ! -f "$flakeDir/flake.nix" ]; then
                echo "Run vm start from the private flake directory." >&2; exit 2
              fi
              stateDir="$dataRoot/$vmName"
              ( umask 077; mkdir -p -- "$stateDir" )
              cd "$stateDir" || exit 1
              systemctl --user reset-failed "$serviceName" 2>/dev/null || true
              systemd-run --user --unit="$serviceName" --same-dir nix run "$flakeDir#$vmName"
              ;;
            status) systemctl --user status "$serviceName" ;;
            logs) journalctl --user -u "$serviceName" -f ;;
            stop)
              socket="/tmp/$vmName-qmp.sock"
              if [ ! -S "$socket" ]; then echo "QMP socket not found: $socket" >&2; exit 1; fi
              {
                echo '{"execute":"qmp_capabilities"}'
                echo '{"execute":"system_powerdown"}'
              } | socat - UNIX-CONNECT:"$socket"
              ;;
            ssh)
              sshArgs=()
              if [ -n "$sshIdentityPath" ]; then sshArgs=(-i "$sshIdentityPath" -o IdentitiesOnly=yes); fi
              ssh "''${sshArgs[@]}" -p "$sshPort" agent@127.0.0.1
              ;;
          esac
          ;;
        *) usage ;;
      esac
    '';
  };
  fishCompletion = pkgs.writeTextFile {
    name = "vm-fish-completion";
    destination = "/share/fish/vendor_completions.d/vm.fish";
    text = ''
      complete -c vm -f
      complete -c vm -n 'test (count (commandline -opc)) -eq 1' -a '${lib.concatStringsSep " " actions}'
      complete -c vm -n 'test (count (commandline -opc)) -eq 2; and contains -- (commandline -opc)[2] start stop status logs ssh destroy' -a '${lib.concatStringsSep " " names}'
    '';
  };
in
pkgs.symlinkJoin {
  name = "vm-cli";
  paths = [ vmScript fishCompletion ];
}