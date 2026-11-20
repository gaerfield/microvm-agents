{ config, pkgs, ... }: {
  imports = [
    ./agent.nix
    ./podman.nix
  ];

  system.stateVersion = "26.11";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  networking.hostName = "my-microvm";
  networking.firewall.allowedTCPPorts = [ 22 ];
  users.users.root.password = "";
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent";
    home = "/home/agent";
    createHome = true;
    password = "";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILSDS1Cu29GbFjeOfUd+p3ztIXQz5wLbuXwQZzx3fP1E agent@microvm.local"
    ];
  };
  security.sudo.enable = false;
  environment.systemPackages = with pkgs; [
    git
  ];

  services.openssh = {
    enable = true;
    # put host-keys in /var/lib/ssh so they stay the same between reboots 
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
    socket = "/tmp/my-microvm-qmp.sock";
    writableStoreOverlay = "/nix/.rw-store";
    interfaces = [
      {
        type = "user";
        id = "usernet";
        mac = "02:00:00:00:00:01";
      }
    ];
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    volumes = [
      {
        mountPoint = "/var";
        image = "var.img";
        size = 256;
      }
    ];
    shares = [
      {
        # use proto = "virtiofs" for MicroVMs that are started by systemd
        proto = "9p";
        tag = "ro-store";
        # a host's /nix/store will be picked up so that no
        # squashfs/erofs will be built for it.
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      {
        # use proto = "virtiofs" for MicroVMs that are started by systemd
        proto = "9p";
        tag = "workspace";
        # a host's /nix/store will be picked up so that no
        # squashfs/erofs will be built for it.
        source = "/home/blaschke/Projects/microvms/one/playground";
        mountPoint = "/playground";
      }
    ];

    # "qemu" has 9p built-in!
    hypervisor = "qemu";
  };

  fileSystems."/nix/.rw-store" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=0755"
      "size=4G"
    ];
  };

}
