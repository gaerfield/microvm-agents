{ ... }:

{
  microvm.volumes = [
    {
      mountPoint = "/home/agent";
      image = "agent-home.img";
      size = 2048;
    }
  ];

  systemd.tmpfiles.rules = [
    "d /home/agent 0700 agent users - -"
  ];
}