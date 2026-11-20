# Disposable AI Agent MicroVMs

## Goal

Run AI coding agents in isolated, disposable NixOS MicroVMs, with **one VM per development task or feature**.

Each VM uses a dedicated Git worktree and the project's existing `devenv` configuration for its development toolchain. No language-specific VM images are necessary.

Example lifecycle:

```bash
vm create server-feature-578 --workspace /path/to/worktree --ssh-port 2224 --identity "$HOME/.ssh/microvm-agent"
vm start server-feature-578
vm ssh server-feature-578
vm stop server-feature-578
vm destroy server-feature-578
vm orphaned
```

`vm create` writes a private instance definition; re-enter `nix develop` before
using the new name. `vm destroy` removes the definition and its persistent VM
images after confirmation, but never deletes a worktree. `vm orphaned` lists
data directories with no matching definition. `vm start` still requires the
private flake directory as its working directory.

## Project layout

```text
microvm-agents/                # Public, reusable library
├── flake.nix
├── modules/
│   ├── base.nix           # QEMU, networking, SSH, Nix
│   ├── agent.nix          # Agent user, CLI, home persistence
│   └── podman.nix         # Rootless Podman, Testcontainers
└── lib/
  ├── mkAgentVM.nix        # Reusable instance factory
  ├── mkInstances.nix      # Instance discovery and flake outputs
  └── vm-cli.nix           # Host-side vm command

microvm-agents-instances/      # Separate private project
├── flake.nix                # Calls public mkInstances with ./instances
└── instances/*.nix          # Task-specific instance definitions
```

Runtime state is kept separately, outside the flake:

```text
~/.local/share/microvm-agents/     # or $XDG_DATA_HOME/microvm-agents/
├── server-feature-578/
│   ├── server-feature-578-var.img
│   ├── server-feature-578-agent-home.img
│   └── server-feature-578-podman.img
└── server-feature-579/
    └── ...
```

Disk images contain the VM's home directory, SSH host keys, `/var`, and Podman
storage. They are **persistent data**, not disposable caches: deleting them
loses the VM's state. This is why the default is `~/.local/share` (or
`$XDG_DATA_HOME`), not `~/.cache`. On hosts with an ephemeral home directory,
ensure this data directory is persistent or set `XDG_DATA_HOME` to a persistent
location before starting a VM.

## Instance factory

Instead of maintaining individual NixOS configurations, use a shared factory:

```nix
mkAgentVM {
  name = "server-feature-578";
  workspace = "/path/to/worktree";
  sshPort = 2222;
  memory = 8192;
  vcpu = 4;
}
```

The factory should:

- Compose the shared NixOS modules.
- Configure the VM's identity, resources and workspace.
- Assign unique SSH ports, QMP sockets and network identifiers.
- Isolate persistent disk images per instance.
- Produce a runnable MicroVM configuration.

The guest username can remain `agent` across all instances.

## Current state

Already working:

- QEMU/KVM MicroVM with user-mode networking.
- SSH access through a forwarded localhost port.
- Writable Nix store overlay.
- Rootless Podman with Docker-compatible API socket.
- VM startup via `systemd-run --user`.
- Graceful shutdown via QMP.
- Host-side lifecycle commands provided through the private flake's dev shell.

Shared guest configuration is now in `modules/base.nix`, `modules/agent.nix`
and `modules/podman.nix`. `lib/mkAgentVM.nix` composes them; the flake
exposes `lib.mkAgentVM` and `lib.mkInstances`. It no longer defines its own VM
or runner; the private flake owns all instances.

### Private instances in a separate flake

Initialize a private instance project in an empty directory:

```bash
nix flake init -t github:gaerfield/microvm-agents
```

The default template contains a small private flake, an example VM definition,
a README, an `.envrc` for nix-direnv, and a `.gitignore`. Edit the example's
absolute `workspace` path and `authorizedKeys` (paste your **public** key text)
before starting it. The example installs Copilot CLI; log in inside the VM,
never in a Nix definition. Run `nix flake lock` to pin the input. If the new
project is a Git repository, add the template files to Git so the flake can
see them. `nix flake init` copies files; it cannot ask for your workspace or
key. See [the template instructions](templates/default/README.md) for details.

Alternatively, create a sibling flake yourself with `microvm-agents` as an
input (`github:gaerfield/microvm-agents`). Its minimal output definition can be:

```nix
outputs = { self, microvm-agents }:
  microvm-agents.lib.mkInstances { inherit self; instancesDir = ./instances; };
```

`mkInstances` discovers the private definitions and exposes VM configurations,
runner packages, and a dev shell with the `vm` command. The dev shell also
installs Fish completions for its actions and discovered instance names; start
Fish after entering the shell to load them. No private
`devenv.nix` or copied scripts are needed; run `nix develop` in that directory
to enter the shell, or `nix develop --command vm status agent-example` to run a
single command. Run `vm start` from the private flake directory: it evaluates
the writable flake from there while starting the VM in its per-instance data
directory under `$XDG_DATA_HOME/microvm-agents` (default:
`~/.local/share/microvm-agents`). Relative image paths resolve there. Running
`nix run .#<name>` directly instead uses the caller's working directory for its
images. Failed systemd units are retained for `vm status` and `vm logs`;
`vm start` clears a previous failure before attempting another start.

For local development before the public library changes are pushed, point the
private flake at the working tree with `nix flake lock --allow-dirty-locks
--override-input microvm-agents git+file:///absolute/path/to/microvm-agents`.
Omit the override to lock the published GitHub version instead. A dirty local
lock is temporary and not reproducible after store garbage collection; switch
back to a published revision when the library changes are pushed. The override
changes the private lock file, not the public input declaration. A private directory outside Git
is a `path:` flake; if you later make it a private Git repo, track its flake
and instance files there. In either case no `--impure` flag or environment
variable is needed. Note that Nix copies instance definitions into the store:
do not place secrets in them.

Each regular `.nix` file in the private `instances/` directory defines one VM.
Its filename without `.nix` is the VM name (for instance, `agent-example.nix`
becomes `vm start agent-example`); do not set `name` in the file. A definition
is an attribute set such as:

```nix
{
  workspace = "/absolute/path/to/worktree";
  sshPort = 2223;
  authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
  sshIdentityPath = "~/.ssh/microvm-agent"; # optional, used by vm ssh on the host
  # memory = 8192;
  # vcpu = 4;
}
```

To install additional guest software, a definition may instead be a function
receiving the pinned `pkgs` set. Existing plain attribute-set definitions
remain valid. For example:

```nix
{ pkgs }:

{
  workspace = "/absolute/path/to/worktree";
  sshPort = 2223;
  authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
  extraPackages = [ pkgs.github-copilot-cli ];
}
```

`extraPackages` defaults to an empty list and adds Nix package values to the
guest's system packages alongside `git`; it does not install tools on the host.
`mkInstances` accepts an optional `pkgs` argument so the same configured
package set can be used by both the instance definitions and the guest; the
private flake uses it to allow the unfree Copilot CLI package specifically.
`vm create` writes a plain definition: edit it into the function form above to
add packages. Rebuild/restart the VM to use a changed package list. Log in to
the CLI separately in the guest; its home directory persists across restarts,
but is removed by `vm destroy`. Never put authentication tokens in Nix files:
their contents are copied into the Nix store.

Give every simultaneously running instance a distinct name and SSH port. The
factory defaults to 8192 MiB RAM and 4 vCPUs; supply `authorizedKeys`
explicitly to allow SSH access. The project worktree is mounted at `/workspace`
inside the guest.

`authorizedKeys` contains public key **contents**, not paths. Nix cannot read
an ignored host file from `~/.ssh` during pure flake evaluation. The optional
`sshIdentityPath` is a host-side path to the matching private key: `vm ssh`
expands a leading `~/` at runtime and uses `ssh -i` with `IdentitiesOnly=yes`.
It is not passed into the guest VM or copied into the Nix store as key data.
Without it, `vm ssh` uses SSH's normal identity selection. Never put private
key contents into a Nix definition.

From the private directory, use `nix run .#agent-example` or enter `nix develop`
and run `vm start agent-example`, `vm status agent-example`, `vm logs
agent-example`, `vm ssh agent-example`, or `vm stop agent-example`. The single
`vm` command requires an action and instance name and rejects unknown values.

Each instance uses name-prefixed image files in its own persistent directory.
`vm destroy` requests a graceful shutdown, waits for the user service to stop,
and only then removes the directory and instance definition; it refuses to
remove state if shutdown cannot be verified. Legacy image files in the private
flake directory and project worktrees are never deleted automatically.

### changing the gitignore file

The [`.gitignore`](.gitignore) file is generated using the service [gitignore.io](https://www.gitignore.io/):
```shell
# get a list of templates
curl -sL https://www.gitignore.io/api/list
# generate a gitignore using the following command:
curl -sL https://www.gitignore.io/api/intellij+all,linux,windows,visualstudiocode
```
The command that were used to generate the [`.gitignore`](/.gitignore) in this repository is
documented in the file itself. Generated content is located at the top of the file. Manually
added content is located at the bottom. When updating the file with new generated patterns,
make sure that the bottom part stays intact.


## Remaining work

### 1. Persistent state follow-up

- Ensure the host data directory survives host impermanence.
- Verify nested mounts and filesystem ownership.

### 2. Agent authentication

- Authenticate using the company account.
- Find a secure way to provision credentials into disposable VMs without requiring login for every instance.
- Avoid sharing a writable agent home directory or exposing host SSH credentials.
- Ensure credentials are removed when an instance is destroyed.

### 3. Instance lifecycle follow-up

- Refresh an existing `nix develop` shell after adding or removing definitions.
- Consider separately managing Git worktrees; destroying a VM never deletes one.

### 4. Development workflow

- Attach a dedicated Git worktree as `/workspace`.
- Use the project's `devenv` for JDK, Gradle, Kotlin and other tools.
- Verify Testcontainers against rootless Podman, preferably with Ryuk enabled.
- Check that the writable Nix store has sufficient capacity.
- Eventually integrate the remote agent workflow with VS Code or IntelliJ.

## Design principles

- **Task-oriented:** one disposable VM per feature or coding task.
- **Reusable:** one shared VM configuration, instantiated with parameters.
- **Minimal:** project-specific tools belong in project `devenv` configurations.
- **Isolated:** separate worktrees, runtime state, container storage and VM endpoints.
- **Recoverable:** restarting a VM preserves its task state.
- **Disposable:** destroying a VM removes its runtime state without affecting the source repository.
- **Rootless:** no root privileges required for normal VM lifecycle operations.

## Next step

Move mutable images to per-instance runtime directories outside the flake
source tree; the factory-generated private example has been validated.

# Links

* [coding-agent-microvm-nix Blog article](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix): thats the original idea 
* [razvanz/nixbox](https://github.com/razvanz/nixbox)
* [hamidr/nixcage](https://github.com/hamidr/nixcage)