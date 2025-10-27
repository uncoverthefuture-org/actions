# Variables Reference

Complete reference for all inputs, outputs, and GitHub context variables used in Uncover Actions.

## Table of Contents

1. [Main Aggregator Inputs](#main-aggregator-inputs)
2. [Build Action Inputs](#build-action-inputs)
3. [Deployment Action Inputs](#deployment-action-inputs)
4. [Output Variables](#output-variables)
5. [GitHub Context Variables](#github-context-variables)
6. [Environment Variables](#environment-variables)

---

## Main Aggregator Inputs

These inputs are passed to the main `uncoverthefuture-org/actions@v1.0.41` action.

### `subaction`

**Type**: `string`  
**Required**: No  
**Default**: (empty)  
**Description**: The sub-action to execute

**Valid Values**:
- `help` - List all available actions
- `build-and-push` - Build and push Docker image
- `ssh-django-deploy` - Deploy Django API
- `ssh-django-api-deploy` - Deploy Django API with Apache
- `ssh-laravel-deploy` - Deploy Laravel app
- `ssh-nextjs-deploy` - Deploy Next.js app
- `ssh-react-deploy` - Deploy React app
- `write-remote-env-file` - Write environment file
- `prepare-ubuntu-host` - Prepare Ubuntu server
- `setup-podman-user` - Setup Podman user
- `remote-podman-exec` - Execute Podman commands
- `podman-run-service` - Run container service
- `podman-login-pull` - Login and pull image
- `podman-stop-rm-container` - Stop and remove container

**Example**:
```yaml
subaction: ssh-django-deploy
```

**Reference**: See ARCHITECTURE.md for category definitions

---

### `category`

**Type**: `string`  
**Required**: No  
**Default**: (auto-detected)  
**Description**: Action category for routing

**Valid Values**:
- `build` - Docker image building
- `app` - Application deployment
- `podman` - Container operations
- `infra` - Infrastructure setup
- `common` - Shared utilities
- `version` - Semantic versioning

**Example**:
```yaml
category: app
```

**Note**: Usually auto-detected from subaction name. Only override if needed.

---

### `params_json`

**Type**: `string` (JSON)  
**Required**: No  
**Default**: (empty)  
**Description**: JSON blob of parameters for the sub-action

**Example**:
```yaml
params_json: |
  {
    "ssh_host": "example.com",
    "ssh_key": "...",
    "env_name": "production",
    "base_domain": "example.com"
  }
```

**Note**: Each sub-action documents its own parameters. See action READMEs.

---

## Build Action Inputs

Inputs for `build-and-push` sub-action.

### `registry`

**Type**: `string`  
**Required**: No  
**Default**: `ghcr.io`  
**Description**: Docker registry hostname

**Valid Values**:
- `ghcr.io` - GitHub Container Registry
- `docker.io` - Docker Hub
- `quay.io` - Quay.io
- Any private registry

**Example**:
```json
{
  "registry": "ghcr.io"
}
```

---

### `image_name`

**Type**: `string`  
**Required**: No  
**Default**: `${{ github.repository }}`  
**Description**: Docker image name (org/repo format)

**Example**:
```json
{
  "image_name": "myorg/myapp"
}
```

**Note**: Defaults to GitHub repository name if not provided.

---

### `image_tag`

**Type**: `string`  
**Required**: No  
**Default**: (auto-generated)  
**Description**: Docker image tag

**Example**:
```json
{
  "image_tag": "abc123def"
}
```

**Note**: Usually auto-generated from commit SHA. Override if needed.

---

### `env_name`

**Type**: `string`  
**Required**: No  
**Default**: (auto-detected)  
**Description**: Environment name (production, staging, development)

**Valid Values**:
- `production` - Production environment
- `staging` - Staging environment
- `development` - Development environment

**Example**:
```json
{
  "env_name": "production"
}
```

**Reference**: See ARCHITECTURE.md for auto-detection rules

---

### `deploy_enabled`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: (auto-detected)  
**Description**: Whether deployment should proceed

**Valid Values**:
- `true` - Enable deployment
- `false` - Skip deployment

**Example**:
```json
{
  "deploy_enabled": "true"
}
```

**Note**: Auto-detected based on branch. Override to force enable/disable.

---

## Deployment Action Inputs

Inputs for deployment actions like `ssh-django-deploy`.

### SSH Configuration

#### `ssh_host`

**Type**: `string`  
**Required**: Yes  
**Description**: SSH host (IP or hostname)

**Example**:
```json
{
  "ssh_host": "192.168.1.100"
}
```

---

#### `ssh_user`

**Type**: `string`  
**Required**: No  
**Default**: `root`  
**Description**: SSH username

**Example**:
```json
{
  "ssh_user": "deployer"
}
```

---

#### `ssh_key`

**Type**: `string`  
**Required**: Yes  
**Description**: SSH private key (PEM format)

**Example**:
```json
{
  "ssh_key": "${{ secrets.SSH_KEY }}"
}
```

**Note**: Should be stored as GitHub secret, never hardcoded.

---

#### `ssh_port`

**Type**: `string`  
**Required**: No  
**Default**: `22`  
**Description**: SSH port

**Example**:
```json
{
  "ssh_port": "2222"
}
```

---

#### `ssh_fingerprint`

**Type**: `string`  
**Required**: No  
**Description**: SSH host key fingerprint for verification

**Example**:
```json
{
  "ssh_fingerprint": "SHA256:abc123..."
}
```

**Note**: Optional but recommended for security.

---

### Host Preparation

#### `prepare_host`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `false`  
**Description**: Whether to prepare a fresh Ubuntu host

**Example**:
```json
{
  "prepare_host": "true"
}
```

**Note**: Set to `true` on first deployment to a new server.

---

#### `install_podman`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `true`  
**Description**: Whether to install Podman during host preparation

**Example**:
```json
{
  "install_podman": "true"
}
```

---

#### `install_traefik`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `true`  
**Description**: Whether to install Traefik during host preparation

**Example**:
```json
{
  "install_traefik": "true"
}
```

**Note**: Required if you want automatic HTTPS with Let's Encrypt.

---

#### `traefik_email`

**Type**: `string`  
**Required**: Conditional  
**Description**: Email for Traefik Let's Encrypt resolver

**Example**:
```json
{
  "traefik_email": "admin@example.com"
}
```

**Note**: Required if `install_traefik: true`.

---

### Environment Configuration

#### `env_name`

**Type**: `string`  
**Required**: No  
**Default**: (auto-detected)  
**Description**: Environment name for deployment

**Example**:
```json
{
  "env_name": "production"
}
```

---

#### `auto_detect_env`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `true`  
**Description**: Whether to auto-detect environment from branch

**Example**:
```json
{
  "auto_detect_env": "true"
}
```

**Reference**: See ARCHITECTURE.md for auto-detection rules

---

#### `env_file_path`

**Type**: `string`  
**Required**: No  
**Default**: `/var/deployments`  
**Description**: Base directory for environment files on server

**Example**:
```json
{
  "env_file_path": "/var/deployments"
}
```

**Note**: Final path is `<env_file_path>/<env_name>/<app_slug>/.env`

---

#### `write_env_file`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `false`  
**Description**: Whether to write .env file on server

**Example**:
```json
{
  "write_env_file": "true"
}
```

---

#### `env_b64`

**Type**: `string` (base64)  
**Required**: Conditional  
**Description**: Base64-encoded .env file contents

**Example**:
```json
{
  "env_b64": "REFUQUJBU0VfVVJMPXBvc3RncmVzcWw6Ly8uLi4="
}
```

**Note**: Required if `write_env_file: true`. Create with: `cat .env | base64`

---

### Container Configuration

#### `image_name`

**Type**: `string`  
**Required**: Yes  
**Description**: Docker image name (org/repo format)

**Example**:
```json
{
  "image_name": "myorg/myapp"
}
```

---

#### `image_tag`

**Type**: `string`  
**Required**: No  
**Default**: (auto-generated)  
**Description**: Docker image tag to deploy

**Example**:
```json
{
  "image_tag": "abc123def"
}
```

---

#### `container_name`

**Type**: `string`  
**Required**: No  
**Default**: `<app_slug>-<env_name>`  
**Description**: Container name on remote server

**Example**:
```json
{
  "container_name": "myapp-prod"
}
```

---

#### `host_port`

**Type**: `string`  
**Required**: No  
**Default**: (from .env or 8000)  
**Description**: Host port for container

**Example**:
```json
{
  "host_port": "8000"
}
```

**Note**: Only used if Traefik is disabled.

---

#### `container_port`

**Type**: `string`  
**Required**: No  
**Default**: (from .env or 8000)  
**Description**: Container internal port

**Example**:
```json
{
  "container_port": "8000"
}
```

---

#### `memory_limit`

**Type**: `string`  
**Required**: No  
**Default**: `512m`  
**Description**: Container memory limit

**Example**:
```json
{
  "memory_limit": "1g"
}
```

---

### Routing Configuration

#### `base_domain`

**Type**: `string`  
**Required**: No  
**Description**: Base domain for Traefik routing

**Example**:
```json
{
  "base_domain": "example.com"
}
```

**Note**: Used to derive full domain with prefixes.

---

#### `domain`

**Type**: `string`  
**Required**: No  
**Description**: Full domain for Traefik routing (overrides base_domain)

**Example**:
```json
{
  "domain": "api.example.com"
}
```

---

#### `domain_prefix_prod`

**Type**: `string`  
**Required**: No  
**Default**: `api`  
**Description**: Domain prefix for production environment

**Example**:
```json
{
  "domain_prefix_prod": "app"
}
```

**Result**: `app.example.com` (if base_domain is `example.com`)

---

#### `domain_prefix_staging`

**Type**: `string`  
**Required**: No  
**Default**: `api-staging`  
**Description**: Domain prefix for staging environment

**Example**:
```json
{
  "domain_prefix_staging": "app-staging"
}
```

---

#### `domain_prefix_dev`

**Type**: `string`  
**Required**: No  
**Default**: `api-dev`  
**Description**: Domain prefix for development environment

**Example**:
```json
{
  "domain_prefix_dev": "app-dev"
}
```

---

#### `enable_traefik`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `true`  
**Description**: Whether to attach Traefik labels to container

**Example**:
```json
{
  "enable_traefik": "true"
}
```

---

### Database Configuration

#### `run_db`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `false`  
**Description**: Whether to run a database container

**Example**:
```json
{
  "run_db": "true"
}
```

---

#### `db_type`

**Type**: `string`  
**Required**: No  
**Default**: `mysql`  
**Description**: Database type

**Valid Values**:
- `mysql` - MySQL database
- `postgres` - PostgreSQL database

**Example**:
```json
{
  "db_type": "postgres"
}
```

---

#### `db_name`

**Type**: `string`  
**Required**: No  
**Description**: Database name

**Example**:
```json
{
  "db_name": "myapp"
}
```

---

#### `db_user`

**Type**: `string`  
**Required**: No  
**Description**: Database user

**Example**:
```json
{
  "db_user": "myapp"
}
```

---

#### `db_password`

**Type**: `string`  
**Required**: No  
**Description**: Database password

**Example**:
```json
{
  "db_password": "${{ secrets.DB_PASSWORD }}"
}
```

**Note**: Should be stored as GitHub secret.

---

### Worker/Scheduler Configuration

#### `run_worker`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `false`  
**Description**: Whether to run a background worker container

**Example**:
```json
{
  "run_worker": "true"
}
```

---

#### `worker_command`

**Type**: `string`  
**Required**: No  
**Description**: Command to run in worker container

**Example**:
```json
{
  "worker_command": "celery -A myapp worker -l info"
}
```

---

#### `run_scheduler`

**Type**: `boolean` (string)  
**Required**: No  
**Default**: `false`  
**Description**: Whether to run a scheduler container

**Example**:
```json
{
  "run_scheduler": "true"
}
```

---

#### `scheduler_command`

**Type**: `string`  
**Required**: No  
**Description**: Command to run in scheduler container

**Example**:
```json
{
  "scheduler_command": "celery -A myapp beat -l info"
}
```

---

## Output Variables

Outputs returned by actions. Access with `${{ steps.<step_id>.outputs.<output_name> }}`.

### Build Outputs

#### `env_name`

**Type**: `string`  
**Description**: Environment name (production, staging, development)

**Example**:
```yaml
${{ steps.build.outputs.env_name }}
# Output: "production"
```

---

#### `env_key`

**Type**: `string`  
**Description**: Environment key (prod, staging, dev)

**Example**:
```yaml
${{ steps.build.outputs.env_key }}
# Output: "prod"
```

---

#### `image_tag`

**Type**: `string`  
**Description**: Docker image tag

**Example**:
```yaml
${{ steps.build.outputs.image_tag }}
# Output: "abc123def"
```

---

#### `deploy_enabled`

**Type**: `string` (boolean)  
**Description**: Whether deployment is enabled

**Example**:
```yaml
${{ steps.build.outputs.deploy_enabled }}
# Output: "true" or "false"
```

---

### Version Outputs

#### `new`

**Type**: `string`  
**Description**: New semantic version

**Example**:
```yaml
${{ steps.version.outputs.new }}
# Output: "v1.2.3"
```

---

#### `major`

**Type**: `string`  
**Description**: Major version alias

**Example**:
```yaml
${{ steps.version.outputs.major }}
# Output: "v1"
```

---

#### `minor`

**Type**: `string`  
**Description**: Minor version alias

**Example**:
```yaml
${{ steps.version.outputs.minor }}
# Output: "v1.2"
```

---

#### `last`

**Type**: `string`  
**Description**: Previous version

**Example**:
```yaml
${{ steps.version.outputs.last }}
# Output: "v1.2.2"
```

---

## GitHub Context Variables

Variables provided by GitHub Actions automatically.

### `github.ref`

**Type**: `string`  
**Description**: Git reference (branch or tag)

**Example**:
```yaml
${{ github.ref }}
# Output: "refs/heads/main" or "refs/tags/v1.0.0"
```

---

### `github.ref_name`

**Type**: `string`  
**Description**: Short ref name (branch or tag name)

**Example**:
```yaml
${{ github.ref_name }}
# Output: "main" or "v1.0.0"
```

---

### `github.sha`

**Type**: `string`  
**Description**: Full commit SHA

**Example**:
```yaml
${{ github.sha }}
# Output: "abc123def456..."
```

---

### `github.repository`

**Type**: `string`  
**Description**: Repository name (owner/repo)

**Example**:
```yaml
${{ github.repository }}
# Output: "myorg/myapp"
```

---

### `github.actor`

**Type**: `string`  
**Description**: User who triggered the workflow

**Example**:
```yaml
${{ github.actor }}
# Output: "john-doe"
```

---

### `github.event.inputs`

**Type**: `object`  
**Description**: Inputs from workflow_dispatch

**Example**:
```yaml
${{ github.event.inputs.level }}
# Output: "patch" or "minor" or "major"
```

---

## Environment Variables

Variables that can be set in your workflow or container.

### Container Environment

#### `DATABASE_URL`

**Type**: `string`  
**Description**: Database connection string

**Example**:
```
postgresql://user:pass@db:5432/myapp
```

---

#### `SECRET_KEY`

**Type**: `string`  
**Description**: Application secret key

**Example**:
```
your-secret-key-here
```

---

#### `DEBUG`

**Type**: `boolean` (string)  
**Description**: Debug mode flag

**Valid Values**:
- `true` - Enable debug mode
- `false` - Disable debug mode

---

#### `PORT` / `API_CONTAINER_PORT`

**Type**: `string`  
**Description**: Container port

**Example**:
```
8000
```

---

#### `API_HOST_PORT`

**Type**: `string`  
**Description**: Host port (if not using Traefik)

**Example**:
```
8000
```

---

### GitHub Actions Environment

#### `GITHUB_TOKEN`

**Type**: `string`  
**Description**: GitHub token for authentication

**Example**:
```yaml
${{ secrets.GITHUB_TOKEN }}
```

**Note**: Automatically provided by GitHub Actions.

---

## Common Patterns

### Using Outputs in Subsequent Steps

```yaml
- id: build
  uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: build-and-push

- name: Deploy
  if: ${{ steps.build.outputs.deploy_enabled == 'true' }}
  uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-django-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_key": "${{ secrets.SSH_KEY }}",
        "env_name": "${{ steps.build.outputs.env_name }}"
      }
```

### Conditional Execution

```yaml
- name: Deploy to Production
  if: ${{ github.ref == 'refs/heads/main' }}
  uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-django-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST_PROD }}",
        "ssh_key": "${{ secrets.SSH_KEY_PROD }}"
      }
```

### Using Secrets

```yaml
params_json: |
  {
    "ssh_host": "${{ secrets.SSH_HOST }}",
    "ssh_key": "${{ secrets.SSH_KEY }}",
    "db_password": "${{ secrets.DB_PASSWORD }}"
  }
```

---

## See Also

- **ARCHITECTURE.md** - How actions work internally
- **GETTING_STARTED.md** - Step-by-step setup guide
- **README.md** - Overview and quick start
- **Action READMEs** - Specific action documentation
