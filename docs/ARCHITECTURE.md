# Uncover Actions - Architecture Guide

## Overview

Uncover Actions is a comprehensive GitHub Actions collection designed for deploying applications to remote Linux hosts using Podman containers over SSH. This document explains the architecture, design decisions, and how everything fits together.

## Design Philosophy

### Why This Architecture?

The project solves several key problems:

1. **Reusability**: Actions are organized by functionality, allowing users to pick and choose what they need
2. **Maintainability**: A single version tag (`@v1.0.41`) covers the entire action suite
3. **Discoverability**: Users can call `subaction: help` to see all available actions
4. **Flexibility**: Supports multiple deployment scenarios (Django, Laravel, React, Next.js, etc.)
5. **Consistency**: All actions follow the same patterns and conventions

### The Aggregator Pattern

Instead of having users reference individual actions like:
```yaml
uses: uncoverthefuture-org/actions/.github/actions/app/ssh-django-deploy@v1.0.41
```

They use a single entry point:
```yaml
uses: uncoverthefuture-org/actions@v1.0.41
with:
  subaction: ssh-django-deploy
```

**Why?** This approach:
- Keeps the main action.yml small and maintainable
- Allows versioning the entire suite with one tag
- Makes it easier to add new actions without changing user workflows
- Provides a consistent interface across all actions

## Directory Structure

```
.github/
├── actions/                    # All reusable actions
│   ├── app/                   # Application deployment actions
│   │   ├── common/            # Shared utilities for app actions
│   │   ├── dispatch/          # Routes to specific app actions
│   │   ├── ssh-django-deploy/
│   │   ├── ssh-django-api-deploy/
│   │   ├── ssh-laravel-deploy/
│   │   ├── ssh-nextjs-deploy/
│   │   ├── ssh-react-deploy/
│   │   └── write-remote-env-file/
│   │
│   ├── build/                 # Docker image building
│   │   ├── build-and-push/    # Main build action
│   │   └── dispatch/          # Routes to build actions
│   │
│   ├── podman/                # Container runtime operations
│   │   ├── dispatch/          # Routes to podman actions
│   │   ├── podman-login-pull/
│   │   ├── podman-run-service/
│   │   ├── podman-stop-rm-container/
│   │   └── remote-podman-exec/
│   │
│   ├── infra/                 # Infrastructure setup
│   │   ├── dispatch/          # Routes to infra actions
│   │   ├── prepare-ubuntu-host/
│   │   └── [other utilities]
│   │
│   ├── common/                # Shared utilities
│   │   ├── dispatch/          # Routes to common actions
│   │   ├── route-category/    # Determines action category
│   │   ├── print-help/        # Lists available actions
│   │   ├── operation-summary/ # Prints execution summary
│   │   └── [other utilities]
│   │
│   └── version/               # Semantic versioning
│       ├── dispatch/          # Routes to version actions
│       ├── compute-next/      # Calculates next version
│       ├── update-refs/       # Updates action references
│       └── update-tags/       # Creates git tags
│
├── examples/                  # Example workflows
│   ├── deploy-django-app.yml
│   ├── deploy-laravel-app.yml
│   ├── deploy-nextjs-app.yml
│   ├── deploy-react-app.yml
│   └── [docker-compose examples]
│
└── workflows/                 # Repository workflows
    └── auto-version.yml       # Automatic versioning
```

## Execution Flow

### How a User Calls an Action

```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-django-deploy
    params_json: |
      {
        "ssh_host": "example.com",
        "ssh_key": "...",
        "env_name": "production"
      }
```

### Step-by-Step Execution

```
1. PREPARE BUNDLED ACTIONS
   └─ Copy all actions from this repo to .github/actions
   └─ Ensures actions are available for dispatcher steps

2. DETERMINE CATEGORY
   └─ route-category action analyzes "ssh-django-deploy"
   └─ Determines it belongs to "app" category
   └─ Output: category = "app"

3. ROUTE TO DISPATCHER
   └─ Only the "app" dispatcher runs (others are skipped)
   └─ app/dispatch receives subaction and params_json

4. DISPATCHER ROUTES TO ACTUAL ACTION
   └─ app/dispatch reads subaction name
   └─ Calls ./.github/actions/app/ssh-django-deploy
   └─ Passes params_json as inputs

5. ACTUAL ACTION EXECUTES
   └─ ssh-django-deploy runs its steps
   └─ Produces outputs (env_name, image_tag, etc.)

6. RESTORE BUNDLED ACTIONS
   └─ Re-copy actions (in case checkout was called)
   └─ Ensures actions are available for subsequent steps

7. OPERATION SUMMARY
   └─ Collects outputs from all dispatchers
   └─ Prints summary to workflow log
```

### Why Prepare and Restore?

GitHub Actions has a known issue where `actions/checkout@v4` can remove bundled actions. The solution:

1. **Prepare**: Copy actions before any checkout steps
2. **Restore**: Re-copy actions after any checkout steps

This ensures bundled actions are always available.

**Reference**: https://github.com/actions/checkout/issues/1467

## Categories

Actions are organized into six categories:

### 1. **build** - Docker Image Building
- **Purpose**: Build and push Docker images to container registries
- **Main Action**: `build-and-push`
- **Key Features**:
  - Automatic environment detection from branch
  - Metadata extraction and tagging
  - Registry authentication

### 2. **app** - Application Deployment
- **Purpose**: Deploy applications to remote servers
- **Actions**:
  - `ssh-django-deploy` - Django API with migrations
  - `ssh-django-api-deploy` - Django API with Apache vhost
  - `ssh-laravel-deploy` - Laravel applications
  - `ssh-nextjs-deploy` - Next.js applications
  - `ssh-react-deploy` - React applications
  - `write-remote-env-file` - Environment file management
- **Key Features**:
  - SSH-based remote execution
  - Traefik routing with Let's Encrypt
  - Database container provisioning
  - Worker and scheduler services
  - Environment auto-detection

### 3. **podman** - Container Runtime Operations
- **Purpose**: Execute container operations on remote hosts
- **Actions**:
  - `remote-podman-exec` - Execute commands via SSH
  - `podman-login-pull` - Registry authentication and image pulling
  - `podman-run-service` - Run long-lived services
  - `podman-stop-rm-container` - Container lifecycle management
- **Key Features**:
  - Rootless container support
  - SSH tunneling for remote execution
  - Volume management
  - Network configuration

### 4. **infra** - Infrastructure Setup
- **Purpose**: Prepare and configure remote hosts
- **Actions**:
  - `prepare-ubuntu-host` - Fresh Ubuntu server setup
  - `apache-manage-vhost` - Apache virtual host management
- **Key Features**:
  - Automated package installation
  - User and permission setup
  - Traefik installation and configuration
  - Apache vhost management (deprecated in favor of Traefik)

### 5. **common** - Shared Utilities
- **Purpose**: Internal utilities used by other actions
- **Actions**:
  - `route-category` - Determines action category
  - `print-help` - Lists available actions
  - `operation-summary` - Prints execution summary
  - `prepare-app-env` - Environment preparation
  - `normalize-params` - Parameter normalization
  - `validate-env-inputs` - Input validation
- **Key Features**:
  - Parameter validation and normalization
  - Environment detection
  - Help and documentation generation

### 6. **version** - Semantic Versioning
- **Purpose**: Manage semantic versioning and git tags
- **Actions**:
  - `compute-next` - Calculate next version
  - `update-refs` - Update action references
  - `update-tags` - Create and update git tags
- **Key Features**:
  - Semantic versioning (semver)
  - Major/minor version aliases
  - Automatic version bumping

## Environment Auto-Detection

The actions automatically map Git refs to canonical environments:

```
Git Ref              → Environment Name → Environment Key
main                 → production        → prod
master               → production        → prod
production           → production        → prod
staging              → staging           → staging
develop              → development       → dev
development          → development       → dev
v1.2.3 (tag)         → production        → prod
feature/xyz          → development       → dev
```

**Override**: Provide `env_name` input to bypass auto-detection.

## Domain Derivation

When `base_domain` is provided, the actions compute a domain for Traefik routing:

```
Environment          + Prefix              = Domain
production           + domain_prefix_prod  = app.example.com
staging              + domain_prefix_staging = api-staging.example.com
development          + domain_prefix_dev   = api-dev.example.com
```

**Override**: Provide `domain` input to use a specific domain.

## Environment File Structure

On the remote server, files are organized as:

```
/var/deployments/
├── production/
│   ├── myapp/
│   │   └── .env
│   └── myapp-worker/
│       └── .env
├── staging/
│   └── myapp/
│       └── .env
└── development/
    └── myapp/
        └── .env
```

**Path**: `<env_dir_path>/<env_name>/<app_slug>/.env`

## SSH Connection Modes

The actions support three SSH connection modes:

### 1. **auto** (default)
- Attempts to connect as `ssh_user` first
- Falls back to `root` if needed
- Automatically handles permission escalation

### 2. **root**
- Connects directly as root
- No permission escalation needed
- Requires root SSH access

### 3. **user**
- Connects as `ssh_user` only
- Uses `sudo` for privileged operations
- Requires passwordless sudo

**Selection**: Provide `connect_mode` input to specify.

## Traefik Routing

When a domain is available, the actions attach Traefik labels to containers:

```yaml
traefik.enable=true
traefik.http.routers.<router>.rule=Host(`app.example.com`)
traefik.http.routers.<router>.entrypoints=websecure
traefik.http.routers.<router>.tls.certresolver=letsencrypt
traefik.http.services.<router>.loadbalancer.server.port=8000
```

**Fallback**: If no domain is provided, containers use host port publishing instead.

**Disable**: Set `enable_traefik: false` to skip Traefik labels.

### Traefik Defaults & Dashboard

- **Default exposure**: `install-traefik.sh` writes `providers.podman.exposedByDefault=false`, so only containers with explicit `traefik.enable=true` labels are routed. This prevents accidental exposure of background containers.
- **Config reuse**: Every Traefik launch invokes `scripts/traefik/ensure-traefik-config.sh` to verify `/etc/traefik/traefik.yml` and `/var/lib/traefik/acme.json` exist with correct ownership (the rootless Podman user) and readable permissions. If either file is missing or unreadable, the script fails fast with remediation instructions (run `install-traefik.sh` as root or fix permissions).
- **Port conflict detection**: `setup-traefik.sh` checks `ss -ltnp` for listeners on 80/443 and aborts with the offending process list so operators can disable Apache/Nginx before retrying.
- **Podman socket detection**: The script prefers `/run/user/<uid>/podman/podman.sock`. If unavailable, it falls back to `/var/run/podman/podman.sock` and emits a notice to enable linger (`loginctl enable-linger <user>`) and restart `podman.socket` under the SSH user to restore fully rootless operation.
- **Dashboard toggle**: Setting `traefik_dashboard=true` (via the deploy inputs) exposes the Traefik dashboard on port 8080 with HTTP→HTTPS redirection and Basic Auth. Supply `traefik_dashboard_user` and a bcrypt hash (`htpasswd -nB`) as `traefik_dashboard_pass_bcrypt`; the setup script mounts these settings and publishes port 8080 automatically.
- **Persistence**: After launching the container, `setup-traefik.sh` runs `podman generate systemd --new --files --name traefik`, installs the resulting unit under `~/.config/systemd/user/`, reloads systemd, and enables the user service so Traefik survives reboots.

### Deployment Status Summary & Privilege Visibility

The `app/deployment-status-summary` composite action records the remote identity on every run:

- `whoami`, `id -u`, and a non-interactive `sudo -n true` probe surface whether commands still run as root.
- When root is detected, the action emits warnings in both the workflow logs and the GitHub Step Summary, providing remediation guidance to reconfigure the SSH user.
- The summary also includes DNS diagnostics (public vs authoritative `dig` results) when Traefik is enabled, helping identify ACME failures caused by stale DNS records.

## Parameter Passing

Parameters are passed as JSON in the `params_json` input:

```yaml
params_json: |
  {
    "ssh_host": "example.com",
    "ssh_key": "...",
    "env_name": "production",
    "base_domain": "example.com",
    "domain_prefix_prod": "app"
  }
```

**Why JSON?** Keeps the main action.yml small and allows arbitrary parameter passing without modifying the aggregator.

## Outputs

Outputs depend on which action runs. The aggregator collects outputs from all dispatchers:

```yaml
# Build outputs
env_name              # Environment name
env_key               # Environment key
image_tag             # Image tag
deploy_enabled        # Whether deployment is enabled

# Common outputs
env_b64               # Base64-encoded .env file
secret_name           # GitHub secret name
secret_found          # Whether secret existed

# Version outputs
new                   # New version (e.g., "v1.2.3")
major                 # Major alias (e.g., "v1")
minor                 # Minor alias (e.g., "v1.2")
last                  # Previous version
```

## Error Handling

The actions follow these error handling principles:

1. **Fail Fast**: Exit immediately on errors with clear messages
2. **Validation**: Validate inputs before executing
3. **Logging**: Print detailed logs for debugging
4. **Rollback**: Clean up on failure (stop containers, remove partial files)

## Security Considerations

1. **SSH Keys**: Passed as GitHub secrets, never logged
2. **Credentials**: Registry tokens handled securely
3. **Host Verification**: Optional SSH host key fingerprint verification
4. **Permissions**: Podman runs as non-root user when possible
5. **Secrets**: Environment files are base64-encoded in transit

## Versioning Strategy

The project uses semantic versioning with aliases:

```
v1.2.3  ← Full version (specific release)
v1.2    ← Minor alias (latest v1.2.x)
v1      ← Major alias (latest v1.x.x)
```

Users can reference:
- `@v1.2.3` - Specific version (no automatic updates)
- `@v1.2` - Latest patch in v1.2 (automatic patch updates)
- `@v1` - Latest in v1 (automatic minor/patch updates)

## Adding New Actions

To add a new action:

1. Create directory: `.github/actions/<category>/<action-name>/`
2. Create `action.yml` with inputs/outputs
3. Create `action.yml` step(s) or shell scripts
4. Add README.md with documentation
5. Update the dispatcher in `.github/actions/<category>/dispatch/`
6. Test with example workflow

## References

- **GitHub Actions Documentation**: https://docs.github.com/en/actions
- **Podman Documentation**: https://podman.io/docs
- **Traefik Documentation**: https://doc.traefik.io/
- **Semantic Versioning**: https://semver.org/

## Troubleshooting

### "Can't find 'action.yml' under '.github/actions/...'"

**Cause**: Missing `actions/checkout@v4` before using local actions.

**Solution**: Add checkout as the first step:
```yaml
- uses: actions/checkout@v4
```

### Actions not found after checkout

**Cause**: `actions/checkout@v4` removed bundled actions.

**Solution**: The aggregator automatically restores them. If you're using actions directly, ensure they're re-prepared.

### SSH connection fails

**Cause**: SSH key permissions or host verification.

**Solution**: 
- Ensure SSH key has correct permissions (600)
- Verify SSH host key fingerprint
- Check SSH_HOST and SSH_KEY secrets are set correctly

### Traefik routing not working

**Cause**: Domain not provided or Traefik not installed.

**Solution**:
- Provide `base_domain` or `domain` input
- Ensure `prepare_host: true` and `install_traefik: true` on first deployment
- Check Traefik container is running: `podman ps | grep traefik`
