# GitHub Actions Collection

Reusable GitHub Actions for deploying containerized applications to remote Linux hosts over SSH using Podman.

This repository is intentionally documented in depth in per-action READMEs and long-form guides under `docs/`. The main README stays **slim** and only describes what the project is and which actions are available.

## What this project is

- **Purpose**: provide a small, composable set of actions for SSH-based container deployments.
- **Primary entry point**: use the aggregated action `uncoverthefuture-org/actions@v1` from your workflows.
- **Default deploy path**: the `ssh-container-deploy` action, which handles generic container deployments (Traefik by default when a domain is available, host ports as a fallback).
- **Package install behavior**: when actions need to run `apt-get update` on the remote host they include `--allow-releaseinfo-change` so noninteractive installs keep working even if trusted repositories update their Release metadata (for example, a PPA changing its `Label`). If you run manual recovery commands, prefer:

  ```bash
  sudo apt-get update -y --allow-releaseinfo-change
  ```

For full details of how deployments work, including examples and configuration, open the **SSH Container Deploy** README in a new tab:

- [SSH Container Deploy README](.github/actions/app/ssh-container-deploy/README.md)

## Available actions (high level)

The main actions you are expected to use are listed below. Each links to a dedicated README with full details.

### Build & deploy

| Action | Description | Docs |
|--------|-------------|------|
| `ssh-container-deploy` | Generic container deployment over SSH (Traefik by default, host ports fallback). **Start here.** | [SSH Container Deploy README](.github/actions/app/ssh-container-deploy/README.md) |
| `build-and-push` | Build and push container images with environment context. | [.github/actions/build-and-push/README.md](.github/actions/build-and-push/README.md) |

For other, more specialized actions (infra helpers, legacy deployers, etc.), see:

- `docs/ACTION_FILES_GUIDE.md` – catalog of all actions and their roles.
