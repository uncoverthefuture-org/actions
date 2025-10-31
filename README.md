# GitHub Actions Collection

A comprehensive, reusable collection of GitHub Actions for deploying applications to remote Linux hosts using Podman containers over SSH. Designed for day-to-day use across multiple projects and environments.

## 🚀 Quick Start

These actions handle the complete deployment pipeline from building images to running containers on remote servers. They support environment-based deployments with automatic directory structure creation and Traefik-managed routing (with Apache still available as an opt-in fallback).

## 📋 Available Actions

The actions are organized into categories. **Primary user-facing actions** are listed in the tables below. Actions in `common/`, `version/`, and some `infra/` directories are internal utilities used by the main actions.

### Build & Deploy Pipeline

| Action | Description | Link |
|--------|-------------|------|
| **Build and Push** | Builds and pushes Docker images with environment context | [README](.github/actions/build-and-push/README.md) |
| **SSH Django Deploy** | Full Django API deployment with migrations and services | [README](.github/actions/app/ssh-django-deploy/README.md) |
| **SSH Django API Deploy** | Django API deployment with Apache vhost management | [README](.github/actions/app/ssh-django-api-deploy/README.md) |
| **SSH Laravel Deploy** | Laravel application deployment | [README](.github/actions/app/ssh-laravel-deploy/README.md) |
| **SSH React Deploy** | React/Next.js application deployment | [README](.github/actions/app/ssh-react-deploy/README.md) |

### Infrastructure Setup

| Action | Description | Link |
|--------|-------------|------|
| **Prepare Ubuntu Host** | Sets up fresh Ubuntu servers for Podman deployments | [README](.github/actions/infra/prepare-ubuntu-host/README.md) |
| **Setup Podman User** _(deprecated)_ | Previously configured Podman user locally; use manual host prep instructions instead | |
| **Apache Manage VHost** | Creates/updates Apache virtual hosts | [README](.github/actions/infra/apache-manage-vhost/README.md) |

### Podman Operations

| Action | Description | Link |
|--------|-------------|------|
| **Remote Podman Exec** | Execute commands on remote hosts with Podman | [README](.github/actions/podman/remote-podman-exec/README.md) |
| **Podman Run Service** | Run long-lived container services | [README](.github/actions/podman/podman-run-service/README.md) |
| **Podman Login Pull** | Secure registry authentication and image pulling | [README](.github/actions/podman/podman-login-pull/README.md) |
| **Podman Stop Remove** | Container lifecycle management | [README](.github/actions/podman/podman-stop-rm-container/README.md) |

### Environment Management

| Action | Description | Link |
|--------|-------------|------|
| **Write Remote Env File** | Manage environment files on remote hosts | [README](.github/actions/app/write-remote-env-file/README.md) |

## 🔧 Key Features

- **Environment-based deployments**: Automatic `/var/deployments/<environment>/<app_slug>/.env` structure with branch-aware detection
- **SSH-based execution**: Secure remote operations with user/key authentication
- **Podman containerization**: Rootless container deployments
- **Traefik reverse proxy**: Automatic router/service labels with Let's Encrypt certificates (Apache vhosts remain optional)
- **Database support**: MySQL/PostgreSQL container deployment
- **Service management**: Background workers and schedulers

## 📁 Directory Structure

```
.github/actions/
├── app/                 # 🚀 Primary deployment actions
│   ├── ssh-django-deploy/
│   ├── ssh-django-api-deploy/
│   ├── ssh-laravel-deploy/
│   ├── ssh-react-deploy/
│   └── write-remote-env-file/
├── infra/              # 🔧 Infrastructure setup (some user-facing)
│   ├── prepare-ubuntu-host/
│   ├── setup-podman-user/ _(deprecated)_
│   ├── apache-manage-vhost/
│   └── [other internal utilities]
├── podman/             # 🐳 Core Podman operations
│   ├── remote-podman-exec/
│   ├── podman-run-service/
│   ├── podman-login-pull/
│   └── podman-stop-rm-container/
├── build/              # 🏗️ Build and CI actions
│   └── build-and-push/
├── common/             # 🛠️ Internal shared utilities
└── version/            # 📦 Internal version management
```

## 🔧 Usage

Each action has its own detailed README with inputs, outputs, and examples. Start with the deployment action that matches your application type, then combine with infrastructure setup actions as needed.

### Default behaviours to know

- **Traefik by default**: When `prepare_host` is used, Traefik is installed and started automatically (`install_traefik=true`). App deploy actions emit Traefik labels whenever a domain can be derived or provided. Set `enable_traefik: false` (per app) to fall back to host port publishing, or `install_traefik: false` during host prep to skip provisioning entirely. Apache vhost actions are now opt-in only.
- **Environment auto-detect**: Deployment actions accept `auto_detect_env` (default `true`) which maps Git refs (`main`, `staging`, `develop`, tags, etc.) to canonical environment folders (`production`, `staging`, `development`). Provide `env_name` to override.
- **Derived domains**: Supplying `base_domain` (and optional `domain_prefix_*`) lets the actions compute a domain used for Traefik routing. A direct `domain` input always wins.

### Per-environment ports and Traefik routing

- **Opinionated defaults**: All app deploy actions accept `host_port` and `container_port`. When you omit them, the scripts now default both ports to `8080` (falling back to `WEB_HOST_PORT`, `WEB_CONTAINER_PORT`, `TARGET_PORT`, or `PORT` when set). Non-Traefik deployments will fail fast with guidance if either port is missing or non-numeric.
- **Collision avoidance for branches**: If you don't use Traefik and publish host ports instead, assign unique `host_port` per environment/branch in your workflow. Example strategy:

  ```yaml
  - name: Compute deployment ports
    id: ports
    run: |
      set -euo pipefail
      ENV_NAME="${{ steps.prep.outputs.env_name }}"
      BRANCH="${GITHUB_REF_NAME:-development}"
      case "$ENV_NAME" in
        production) HOST_PORT=3000 ;;
        staging) HOST_PORT=3001 ;;
        *) # Deterministic 3200-3899 range per branch
           if command -v sha1sum >/dev/null 2>&1; then HHEX=$(printf '%s' "$BRANCH" | sha1sum | cut -c1-6); else HHEX=$(printf '%s' "$BRANCH" | shasum -a 1 | awk '{print $1}' | cut -c1-6); fi
           HDEC=$((16#$HHEX)); HOST_PORT=$((3200 + (HDEC % 700))) ;;
      esac
      echo "host_port=$HOST_PORT" >> "$GITHUB_OUTPUT"
      echo "container_port=3000" >> "$GITHUB_OUTPUT"
  - name: Deploy App
    uses: uncoverthefuture-org/actions@master
    with:
      subaction: ssh-nextjs-deploy
      params_json: |
        {
          "ssh_host": "${{ secrets.SERVER_HOST }}",
          "ssh_user": "${{ secrets.SERVER_USER }}",
          "ssh_key":  "${{ secrets.SERVER_SSH_KEY }}",
          "host_port": "${{ steps.ports.outputs.host_port }}",
          "container_port": "${{ steps.ports.outputs.container_port }}"
        }
  ```

- **Traefik on/off switch**:
  - Pass a `domain` or `base_domain` to enable Traefik routing with automatic TLS. Optionally set `enable_traefik: true` (default) to attach labels. When Traefik mode is active, any supplied `host_port` is ignored and a notice is emitted because Traefik terminates traffic on ports 80/443.
  - Omit `domain`/`base_domain` (or set `enable_traefik: false`) to publish `-p host:container` instead. This avoids port 80/443 and lets multiple branches run side-by-side.
  - When using `prepare_host: true`, Traefik can be provisioned with `install_traefik: true` and `traefik_email` (Let's Encrypt). To open firewall ports during preparation, set `ufw_allow_ports` (e.g., "22 80 443 3000 3001").
  - Optional dashboard: set `traefik_dashboard: true` together with `traefik_dashboard_user` and `traefik_dashboard_pass_bcrypt` (bcrypt hash from `htpasswd -nB`). The shared setup script automatically maps port 8080, enables HTTPS redirects, and guards the dashboard behind HTTP basic auth. The installer also seeds `/etc/traefik/dashboard-users` so you can add credentials later if you defer the hash.
  - Config reuse: every Traefik run calls `scripts/traefik/ensure-traefik-config.sh` to verify `/etc/traefik/traefik.yml` and `/var/lib/traefik/acme.json` exist with the correct ownership (rootless podman user). If permissions are wrong, the action fails fast with remediation steps.
  - Podman socket detection: if the per-user podman socket is unavailable, the setup script falls back to `/var/run/podman/podman.sock` and logs guidance for enabling linger / restarting `podman.socket` under the SSH user before the next deploy.
  - Disable ACME temporarily by passing `enable_acme: false`; the deployment action skips the `traefik.http.routers.*.tls.certresolver` label so Traefik runs without hitting Let's Encrypt while you debug port 80. Re-enable once connectivity is restored. When ACME is off, downstream labels automatically switch to the `web` entrypoint so HTTP continues to work.
  - Healthchecks: leave `enable_ping: true` (default) so `podman exec traefik traefik healthcheck` works; the setup script wires the ping entrypoint automatically.
  - Networking & metrics toggles: use `use_host_network: true` to run Traefik in host network mode (bypasses `-p` while debugging port 80) or leave it `false` to publish `80/443/8080/8082`. Provide `network_name` (defaults to `traefik-network`) so Traefik and app containers share a Podman network; the deploy script will create/connect the network automatically. Enable Prometheus metrics by setting `enable_metrics: true` (override `metrics_entrypoint`/`metrics_address` if desired).

### Example Workflow

```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy Django API
        uses: uncoverthefuture-org/actions/.github/actions/app/ssh-django-deploy@master
        with:
          ssh_host: ${{ secrets.SSH_HOST }}
          ssh_user: ${{ secrets.SSH_USER }}
          ssh_key: ${{ secrets.SSH_KEY }}
          env_name: production
          image_name: ${{ github.repository }}
          image_tag: ${{ github.sha }}
```

### ⚠️ Important Notes

- **Bundled Actions Auto-Restored**: The aggregator automatically rehydrates `.github/actions` via `common/ensure-bundled-actions`, so downstream steps continue to work after any `actions/checkout`
- **Checkout Required**: When using these actions in workflows, ensure you have `actions/checkout` before using any local actions (`.github/actions/...`)
- **Internal Actions**: Actions in `common/` and `version/` directories are internal utilities and should not be used directly
- **SSH Access**: Ensure your deployment targets have SSH access configured with the specified users and keys
- **User-Owned Directories**: All scripts now assume deployment paths (e.g. `/var/deployments/<env>/<app>`) are writable by the SSH user. Prefer locations inside the user's home (e.g. `$HOME/deployments`) or adjust ownership (`chown -R <ssh_user> <path>`) before running actions; otherwise the scripts will fail fast with guidance.
- **Automatic Host Port Mapping**: `ssh-container-deploy` persists the selected host port for each app/env in `.host-port` inside the deployment directory. If the preferred port (default `8080`) is occupied, the deploy script finds the next available port, records it for future runs, and reuses any previously assigned value unless you override `host_port` explicitly.

## 🚨 Troubleshooting

### "Can't find 'action.yml' under '/home/runner/work/.../.github/actions/...'"

**Cause**: Missing `actions/checkout` step before using local actions.

**Solution**: Add checkout as the first step in your workflow:

```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v4
  # ... your deployment steps
```

## 🤝 Contributing

Actions are organized by functionality. When adding new actions:

1. Follow the directory structure
2. Include comprehensive README.md files
3. Use consistent input/output patterns
4. Support the standard SSH authentication model

## 📚 Documentation

For detailed usage of each action, click the links in the table above or navigate to the action's directory.

> 🔐 **SSH User Enforcement**
>
> All remote execution now runs strictly as the `ssh_user` supplied to composite
> actions. Provision servers with the desired account ahead of time and ensure
> deployment directories are owned by that user. Avoid workflows that attempt to
> escalate privileges or create alternate Podman users—those patterns have been
> removed across the action catalog.
