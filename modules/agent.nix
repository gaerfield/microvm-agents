{ name, authorizedKeys, ... }:

{
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent";
    home = "/home/agent";
    createHome = true;
    password = "";
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  microvm.volumes = [
    {
      mountPoint = "/home/agent";
      image = "${name}-agent-home.img";
      size = 2048;
    }
  ];

  systemd.tmpfiles.rules = [
    "d /home/agent 0700 agent users - -"
  ];
}