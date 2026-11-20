{ name, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
  };

  users.users.agent = {
    subUidRanges = [ { startUid = 100000; count = 65536; } ];
    subGidRanges = [ { startGid = 100000; count = 65536; } ];
  };

  systemd.user.sockets.podman.wantedBy = [ "sockets.target" ];

  environment.sessionVariables.DOCKER_HOST =
    "unix:///run/user/1000/podman/podman.sock";

  microvm.volumes = [
    {
      mountPoint = "/home/agent/.local/share/containers";
      image = "${name}-podman.img";
      size = 16384;
    }
  ];

  systemd.tmpfiles.rules = [
    "d /home/agent/.local/share/containers 0700 agent users - -"
  ];
}