# Private MicroVM instances

This project uses [microvm-agents](https://github.com/gaerfield/microvm-agents)
to run one agent MicroVM per Git worktree. The example installs Copilot CLI in
the guest; the flake permits that unfree package specifically. No credentials
are included.

## Set up

1. Edit `instances/agent-example.nix`: set `workspace` to an existing absolute
   host path and paste your **public** SSH key contents into `authorizedKeys`.
   Optionally set `sshIdentityPath` to your matching private key **path** for
   `vm ssh`. Never paste private keys or tokens into Nix files: they are copied
   into the Nix store. Rename the instance file to choose a different VM name.
2. Run `nix flake lock` and `nix develop` in this directory to get the `vm`
   command. If using a Git-backed flake, track the instance and configuration
   files so Nix can see them.
3. Optionally install `direnv` and `nix-direnv`, enable the direnv shell hook,
   and run `direnv allow`. The included `.envrc` then loads the dev shell
   automatically when you enter the directory. Restart Fish after entering
   the shell to load completions if needed.
4. Run `vm start agent-example`, then `vm ssh agent-example`. Authenticate the
   agent CLI **inside** the VM; its home persists across restarts but is
   deleted by `vm destroy`.

Other instances go in `instances/<name>.nix`. `vm create` can generate a basic
definition; edit it into the `{ pkgs }: { ... }` form to add guest packages
using `extraPackages = [ pkgs.somePackage ];`. Only Copilot CLI is permitted
as an unfree package by this template; update the predicate for other unfree
packages. Use a unique `sshPort` for each VM.

The VM state lives under `$XDG_DATA_HOME/microvm-agents/<name>` (by default,
`~/.local/share/microvm-agents/<name>`). `vm destroy` removes that state and
the instance definition, but not the Git worktree. See the upstream README
for the full lifecycle and persistence details.