{ pkgs, name, workspace, sshPort, memory, vcpu, mac, ... }:

{
  system.stateVersion = "26.11";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.hostName = name;
  networking.firewall.allowedTCPPorts = [ 22 ];

  users.users.root.password = "";
  security.sudo.enable = false;
  environment.systemPackages = with pkgs; [ git ];

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  microvm = {
    hypervisor = "qemu";
    socket = "/tmp/${name}-qmp.sock";
    mem = memory;
    vcpu = vcpu;
    writableStoreOverlay = "/nix/.rw-store";
    interfaces = [
      {
        type = "user";
        id = "usernet";
        inherit mac;
      }
    ];
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = sshPort;
        guest.port = 22;
      }
    ];
    volumes = [
      {
        mountPoint = "/var";
        image = "${name}-var.img";
        size = 256;
      }
    ];
    shares = [
      {
        proto = "9p";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      {
        proto = "9p";
        tag = "workspace";
        source = workspace;
        mountPoint = "/workspace";
      }
    ];
  };

  fileSystems."/nix/.rw-store" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" "size=4G" ];
  };
}