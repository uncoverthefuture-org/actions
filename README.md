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
| **Setup Podman User** | Configures Podman user and permissions | [README](.github/actions/infra/setup-podman-user/README.md) |
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
│   ├── setup-podman-user/
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
