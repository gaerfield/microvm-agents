{ pkgs }:

{
  # Replace with an existing absolute path to your Git worktree.
  workspace = "/absolute/path/to/worktree";
  sshPort = 2223;
  memory = 8192;
  vcpu = 4;
  extraPackages = [ pkgs.github-copilot-cli ];

  # Paste the CONTENTS of your public SSH key here before starting the VM.
  # Never put a private key or an authentication token in this file.
  authorizedKeys = [ ];
  # sshIdentityPath = "~/.ssh/microvm-agent"; # Optional host-side private key path.
}