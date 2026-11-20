# Disposable AI Agent MicroVMs

## Goal

Run AI coding agents in isolated, disposable NixOS MicroVMs, with **one VM per development task or feature**.

Each VM uses a dedicated Git worktree and the project's existing `devenv` configuration for its development toolchain. No language-specific VM images are necessary.

Example lifecycle:

```bash
vm-create server-feature-578 --workspace /path/to/worktree
vm-start server-feature-578
vm-ssh server-feature-578
vm-stop server-feature-578
vm-destroy server-feature-578
```

These commands describe the **planned interface**, not the current implementation.

## Planned directory structure

```text
microvms/
├── flake.nix
├── devenv.nix             # Host-side VM lifecycle commands
├── modules/
│   ├── base.nix           # QEMU, networking, SSH, Nix
│   ├── agent.nix          # Agent user, CLI, home persistence
│   └── podman.nix         # Rootless Podman, Testcontainers
├── lib/
│   └── mkAgentVM.nix      # Reusable instance factory
└── instances/
    └── ...                # Task-specific instance definitions
```

Runtime state is kept separately, outside the flake:

```text
~/.local/share/microvms/
├── server-feature-578/
│   ├── var.img
│   ├── agent-home.img
│   └── podman.img
└── server-feature-579/
    └── ...
```

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
- Host-side lifecycle scripts in `devenv.nix`.

Shared guest configuration is now in `modules/base.nix`, `modules/agent.nix`
and `modules/podman.nix`. `lib/mkAgentVM.nix` composes them; the flake
exposes `lib.mkAgentVM`. `instances/agent-example.nix` defines an independent
`agent-example` instance with its own SSH port (2223), QMP socket, MAC address
and disk image names. The original `my-microvm` configuration and default
runner remain unchanged as the working reference.

To configure another instance, add a `.nix` file like
`instances/agent-example.nix` to the `instances/` directory. Its filename
without `.nix` is the VM name (for instance, `agent-example.nix` becomes
`vm-start agent-example`); do not set `name` in the file. The flake and host
lifecycle scripts discover these files automatically. Give every simultaneously
running instance a distinct name and SSH port. The factory defaults to 8192
MiB RAM and 4 vCPUs; supply
`authorizedKeys` explicitly to allow SSH access. The project worktree is
mounted at `/workspace` (the reference VM still mounts `/playground`).

Run `vm-start agent-example`, `vm-status agent-example`, `vm-logs agent-example`,
`vm-ssh agent-example`, or `vm-stop agent-example` to manage the new instance.
Omitting the name in any of these commands continues to select the original
`my-microvm` reference VM (and preserves its existing SSH alias). Unknown
instance names are rejected.

The new instance currently uses name-prefixed image files relative to the
runner's working directory. Persistent per-instance runtime directories and
`vm-create`/`vm-destroy` commands are the next step; do not start two runners
with the same instance name or working directory images. Existing image files
in the repository root belong to the reference VM and are not migrated.

## Remaining work

### 1. Persistent state

- Give every instance its own runtime directory.
- Persist `/var`, `/home/agent` and rootless Podman storage across VM restarts.
- Ensure runtime directories survive host impermanence.
- Keep mutable disk images outside the Nix flake source tree.
- Verify nested mounts and filesystem ownership.

### 2. Agent installation and authentication

- Install and configure GitHub Copilot CLI (and optionally Codex CLI).
- Authenticate using the company account.
- Find a secure way to provision credentials into disposable VMs without requiring login for every instance.
- Avoid sharing a writable agent home directory or exposing host SSH credentials.
- Ensure credentials are removed when an instance is destroyed.

### 3. Instance lifecycle

Implement commands such as:

```text
vm-create
vm-start
vm-stop
vm-status
vm-logs
vm-ssh
vm-destroy
```

`vm-destroy` should stop the VM and remove its instance-specific runtime state, including Podman images and containers. Deleting the Git worktree should be a separate, explicit operation to avoid losing uncommitted changes.

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

Validate the factory-generated example VM against the still-working reference,
then move its mutable images to per-instance runtime directories outside the
flake source tree. Do not remove the reference VM before that validation.

# changing the gitignore file

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


