{ ... }: {
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
  };

  users.users.agent = {
    subUidRanges = [
      { startUid = 100000; count = 65536; }
    ];

    subGidRanges = [
      { startGid = 100000; count = 65536; }
    ];
  };

  
  # Start the rootless Podman API socket for the agent user
  systemd.user.sockets.podman.wantedBy = [ "sockets.target" ];

  # Environment for Docker-compatible clients such as Testcontainers
  environment.sessionVariables = {
    DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock";
    # Ryuk is Testcontainers' resource cleanup service.
    # its not sure that it works with podman
    # TESTCONTAINERS_RYUK_DISABLED = "true";
  };

  # don't loose vm-images between vm restarts
  microvm.volumes = [
    {
      mountPoint = "/home/agent/.local/share/containers";
      image = "podman.img";
      size = 16384;
    }
  ];
  # and take care of the ownership
  systemd.tmpfiles.rules = [
    "d /home/agent/.local/share/containers 0700 agent users - -"
  ];
}