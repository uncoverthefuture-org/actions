# Action Files Guide

Complete reference for all action files in the Uncover Actions project. This guide explains what each action does and where to find it.

## 📁 Directory Structure Overview

```
.github/actions/
├── app/                          # Application deployment actions
│   ├── common/                   # Shared utilities for app actions
│   ├── dispatch/                 # Routes to specific app actions
│   ├── ssh-django-deploy/        # Deploy Django API
│   ├── ssh-django-api-deploy/    # Deploy Django API with Apache
│   ├── ssh-laravel-deploy/       # Deploy Laravel app
│   ├── ssh-nextjs-deploy/        # Deploy Next.js app
│   ├── ssh-react-deploy/         # Deploy React app
│   └── write-remote-env-file/    # Write environment files
│
├── build/                        # Docker image building
│   ├── build-and-push/           # Build and push Docker image
│   └── dispatch/                 # Routes to build actions
│
├── podman/                       # Container runtime operations
│   ├── dispatch/                 # Routes to podman actions
│   ├── podman-login-pull/        # Login to registry and pull image
│   ├── podman-run-service/       # Run long-lived container service
│   ├── podman-stop-rm-container/ # Stop and remove container
│   └── remote-podman-exec/       # Execute commands on remote host
│
├── infra/                        # Infrastructure setup
│   ├── dispatch/                 # Routes to infra actions
│   ├── prepare-ubuntu-host/      # Prepare fresh Ubuntu server
│   ├── apache-manage-vhost/      # Manage Apache virtual hosts
│   ├── certbot/                  # SSL certificate management
│   └── [other utilities]
│
├── common/                       # Shared utilities
│   ├── dispatch/                 # Routes to common actions
│   ├── route-category/           # Determine action category
│   ├── print-help/               # List available actions
│   ├── operation-summary/        # Print execution summary
│   ├── prepare-app-env/          # Prepare environment
│   ├── normalize-params/         # Normalize parameters
│   ├── validate-env-inputs/      # Validate inputs
│   ├── lint-uses/                # Lint action uses
│   ├── cleanup-runner/           # Cleanup runner
│   └── [other utilities]
│
└── version/                      # Semantic versioning
    ├── dispatch/                 # Routes to version actions
    ├── compute-next/             # Calculate next version
    ├── update-refs/              # Update action references
    └── update-tags/              # Create git tags
```

---

## 🚀 Primary User-Facing Actions

These are the main actions users call directly.

### Build Actions

#### **build-and-push**
**Location**: `.github/actions/build/build-and-push/action.yml`

**Purpose**: Build Docker image and push to container registry

**What it does**:
1. Logs in to Docker registry
2. Extracts metadata (tags, labels)
3. Builds Docker image
4. Pushes image to registry

**Key inputs**:
- `registry` - Docker registry (default: ghcr.io)
- `image_name` - Image name (default: github.repository)
- `image_tag` - Image tag
- `env_name` - Environment name (auto-detected)
- `deploy_enabled` - Whether to deploy (auto-detected)

**Key outputs**:
- `env_name` - Environment name
- `image_tag` - Image tag
- `deploy_enabled` - Whether deployment is enabled

**When to use**: First step in CI/CD pipeline to build and push images

**Reference**: See VARIABLES_REFERENCE.md - Build Action Inputs

---

### App Deployment Actions

#### **ssh-django-deploy**
**Location**: `.github/actions/app/ssh-django-deploy/action.yml`

**Purpose**: Deploy Django API application to remote server

**What it does**:
1. Optionally prepares host (Podman, Traefik)
2. Writes environment file
3. Logs in to registry and pulls image
4. Runs migrations
5. Starts Django container
6. Optionally starts worker and scheduler

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `image_name` - Docker image name (required)
- `base_domain` - Domain for Traefik routing
- `run_db` - Whether to run database container
- `run_worker` - Whether to run worker
- `run_scheduler` - Whether to run scheduler

**Key features**:
- Automatic environment detection
- Traefik routing with Let's Encrypt
- Database container provisioning
- Worker and scheduler support
- Migration execution

**When to use**: Deploy Django APIs to production/staging/development

**Reference**: See VARIABLES_REFERENCE.md - Deployment Action Inputs

---

#### **ssh-django-api-deploy**
**Location**: `.github/actions/app/ssh-django-api-deploy/action.yml`

**Purpose**: Deploy Django API with Apache vhost management

**What it does**:
- Similar to ssh-django-deploy
- Includes Apache vhost configuration
- Manages reverse proxy setup

**Key difference**: Uses Apache instead of Traefik (deprecated)

**When to use**: Legacy deployments using Apache

**Note**: Traefik is now preferred. Use ssh-django-deploy instead.

---

#### **ssh-laravel-deploy**
**Location**: `.github/actions/app/ssh-laravel-deploy/action.yml`

**Purpose**: Deploy Laravel application to remote server

**What it does**:
1. Prepares host (optional)
2. Writes environment file
3. Pulls Docker image
4. Runs Laravel migrations
5. Starts Laravel container
6. Optionally starts worker and scheduler

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `image_name` - Docker image name (required)
- `base_domain` - Domain for routing
- `run_worker` - Background worker
- `run_scheduler` - Scheduler/cron

**When to use**: Deploy Laravel applications

---

#### **ssh-nextjs-deploy**
**Location**: `.github/actions/app/ssh-nextjs-deploy/action.yml`

**Purpose**: Deploy Next.js application to remote server

**What it does**:
1. Prepares host (optional)
2. Pulls Docker image
3. Starts Next.js container
4. Configures Traefik routing

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `image_name` - Docker image name (required)
- `base_domain` - Domain for routing

**When to use**: Deploy Next.js applications

---

#### **ssh-react-deploy**
**Location**: `.github/actions/app/ssh-react-deploy/action.yml`

**Purpose**: Deploy React application to remote server

**What it does**:
1. Prepares host (optional)
2. Pulls Docker image
3. Starts React container
4. Configures Traefik routing

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `image_name` - Docker image name (required)
- `base_domain` - Domain for routing

**When to use**: Deploy React applications

---

#### **write-remote-env-file**
**Location**: `.github/actions/app/write-remote-env-file/action.yml`

**Purpose**: Write environment file to remote server

**What it does**:
1. Connects via SSH
2. Creates directory structure
3. Decodes base64-encoded .env file
4. Writes to remote server

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `env_name` - Environment name
- `env_b64` - Base64-encoded .env contents
- `env_file_path` - Base directory for .env

**When to use**: Manage environment files on remote servers

**Reference**: See GETTING_STARTED.md - Step 2 (GitHub Secrets)

---

### Infrastructure Actions

#### **prepare-ubuntu-host**
**Location**: `.github/actions/infra/prepare-ubuntu-host/action.yml`

**Purpose**: Prepare fresh Ubuntu server for deployments

**What it does**:
1. Updates package manager
2. Installs Podman
3. Creates deployment directories
4. Installs Traefik (optional)
5. Installs additional packages

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key for the session user (required)
- `install_podman` - Install Podman (default: true)
- `install_traefik` - Install Traefik (default: true)
- `traefik_email` - Email for Let's Encrypt

> ℹ️ All host preparation now runs as the caller-provided `ssh_user`. The legacy
> `create_podman_user` toggle has been removed—provision target users manually
> during infrastructure setup and keep directory ownership aligned with that user.

**When to use**: First deployment to a new server

**Reference**: See GETTING_STARTED.md - Step 1

---

#### **setup-podman-user** _(removed)_
**Location**: `.github/actions/infra/setup-podman-user/action.yml`

> ⚠️ This action has been removed. All remote operations run strictly as the provided
> `ssh_user`. Provision the target user during infrastructure setup and keep directory
> ownership aligned with that user. Remove any references to `setup-podman-user` from
> workflows and documentation.

---

#### **apache-manage-vhost**
**Location**: `.github/actions/infra/apache-manage-vhost/action.yml`

**Purpose**: Create/update Apache virtual hosts

**What it does**:
1. Creates Apache vhost configuration
2. Enables vhost
3. Reloads Apache

**Note**: Deprecated in favor of Traefik

**When to use**: Legacy Apache-based deployments

---

### Podman Actions

#### **remote-podman-exec**
**Location**: `.github/actions/podman/remote-podman-exec/action.yml`

**Purpose**: Execute commands on remote host via SSH

**What it does**:
1. Connects via SSH
2. Sources environment file (optional)
3. Executes inline script
4. Returns output

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `inline_script` - Script to execute (required)
- `env_file_path` - Path to .env file
- `source_env` - Whether to source .env (default: true)

**When to use**: Execute custom commands on remote servers

**Example**: Run migrations, restart services, etc.

---

#### **podman-login-pull**
**Location**: `.github/actions/podman/podman-login-pull/action.yml`

**Purpose**: Authenticate with registry and pull image

**What it does**:
1. Connects via SSH
2. Logs in to registry
3. Pulls Docker image

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `registry` - Registry hostname
- `registry_username` - Registry username
- `registry_token` - Registry token/password
- `image_name` - Image to pull (required)
- `image_tag` - Image tag (required)

**When to use**: Pull images before deployment

---

#### **podman-run-service**
**Location**: `.github/actions/podman/podman-run-service/action.yml`

**Purpose**: Run long-lived container service

**What it does**:
1. Connects via SSH
2. Starts container
3. Configures restart policy
4. Sets up volumes and environment

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `service_name` - Container name (required)
- `image` - Docker image (required)
- `command` - Command to run
- `env_file` - Environment file path
- `restart_policy` - Restart policy
- `memory_limit` - Memory limit
- `volumes` - Volume mounts

**When to use**: Run background workers, schedulers, databases

---

#### **podman-stop-rm-container**
**Location**: `.github/actions/podman/podman-stop-rm-container/action.yml`

**Purpose**: Stop and remove container

**What it does**:
1. Connects via SSH
2. Stops container
3. Removes container

**Key inputs**:
- `ssh_host` - SSH host (required)
- `ssh_key` - SSH private key (required)
- `container_name` - Container to remove (required)

**When to use**: Cleanup before redeployment

---

## 🔧 Internal Utility Actions

These actions are used internally by other actions. Users typically don't call them directly.

### Common Utilities

#### **route-category**
**Location**: `.github/actions/common/route-category/action.yml`

**Purpose**: Determine action category from subaction name

**What it does**:
- Analyzes subaction name
- Returns category (build, app, podman, infra, common, version)

**Used by**: Main aggregator action

---

#### **print-help**
**Location**: `.github/actions/common/print-help/action.yml`

**Purpose**: List all available actions

**What it does**:
- Prints help message
- Lists available subactions
- Shows usage examples

**Used by**: Main aggregator when `subaction: help`

---

#### **operation-summary**
**Location**: `.github/actions/common/operation-summary/action.yml`

**Purpose**: Print execution summary

**What it does**:
- Collects outputs from all dispatchers
- Formats summary
- Prints to workflow log

**Used by**: Main aggregator after execution

---

#### **prepare-app-env**
**Location**: `.github/actions/common/prepare-app-env/action.yml`

**Purpose**: Prepare application environment

**What it does**:
- Detects environment from branch
- Resolves environment variables
- Prepares deployment context

**Used by**: App deployment actions

---

#### **normalize-params**
**Location**: `.github/actions/common/normalize-params/action.yml`

**Purpose**: Normalize input parameters

**What it does**:
- Parses JSON parameters
- Validates parameter types
- Provides defaults

**Used by**: All actions

---

#### **lint-uses**
**Location**: `.github/actions/common/lint-uses/action.yml`

**Purpose**: Validate action.yml files

**What it does**:
- Checks syntax
- Validates references
- Reports errors

**Used by**: CI/CD validation

---

#### **cleanup-runner**
**Location**: `.github/actions/common/cleanup-runner/action.yml`

**Purpose**: Cleanup GitHub Actions runner

**What it does**:
- Removes temporary files
- Clears caches
- Frees disk space

**Used by**: End of workflows

---

### Dispatcher Actions

#### **app/dispatch**
**Location**: `.github/actions/app/dispatch/action.yml`

**Purpose**: Route to specific app action

**What it does**:
- Reads subaction name
- Calls appropriate app action
- Collects outputs

**Used by**: Main aggregator for app category

---

#### **build/dispatch**
**Location**: `.github/actions/build/dispatch/action.yml`

**Purpose**: Route to specific build action

**What it does**:
- Reads subaction name
- Calls appropriate build action
- Collects outputs

**Used by**: Main aggregator for build category

---

#### **podman/dispatch**
**Location**: `.github/actions/podman/dispatch/action.yml`

**Purpose**: Route to specific podman action

**What it does**:
- Reads subaction name
- Calls appropriate podman action
- Collects outputs

**Used by**: Main aggregator for podman category

---

#### **infra/dispatch**
**Location**: `.github/actions/infra/dispatch/action.yml`

**Purpose**: Route to specific infra action

**What it does**:
- Reads subaction name
- Calls appropriate infra action
- Collects outputs

**Used by**: Main aggregator for infra category

---

#### **common/dispatch**
**Location**: `.github/actions/common/dispatch/action.yml`

**Purpose**: Route to specific common action

**What it does**:
- Reads subaction name
- Calls appropriate common action
- Collects outputs

**Used by**: Main aggregator for common category

---

#### **version/dispatch**
**Location**: `.github/actions/version/dispatch/action.yml`

**Purpose**: Route to specific version action

**What it does**:
- Reads subaction name
- Calls appropriate version action
- Collects outputs

**Used by**: Main aggregator for version category

---

### Version Actions

#### **compute-next**
**Location**: `.github/actions/version/compute-next/action.yml`

**Purpose**: Calculate next semantic version

**What it does**:
- Reads current git tags
- Analyzes commit history
- Calculates next version
- Returns version and aliases

**Key inputs**:
- `level` - Bump level (patch, minor, major)

**Key outputs**:
- `new` - New version (e.g., v1.2.3)
- `major` - Major alias (e.g., v1)
- `minor` - Minor alias (e.g., v1.2)
- `last` - Previous version

**Used by**: Auto-versioning workflow

---

#### **update-refs**
**Location**: `.github/actions/version/update-refs/action.yml`

**Purpose**: Update action references to new version

**What it does**:
- Finds all action.yml files
- Updates version references
- Commits changes

**Key inputs**:
- `new_tag` - New version tag
- `force` - Force update (default: false)

**Used by**: Auto-versioning workflow

---

#### **update-tags**
**Location**: `.github/actions/version/update-tags/action.yml`

**Purpose**: Create git tags for release

**What it does**:
- Creates full version tag
- Creates major alias tag
- Creates minor alias tag
- Pushes tags to repository

**Key inputs**:
- `new` - Full version (e.g., v1.2.3)
- `major` - Major alias (e.g., v1)
- `minor` - Minor alias (e.g., v1.2)
- `tag_message` - Tag message

**Used by**: Auto-versioning workflow

---

## 📊 Action Categories Summary

| Category | Count | Purpose |
|----------|-------|---------|
| **app** | 8 | Application deployment |
| **build** | 2 | Docker image building |
| **podman** | 5 | Container operations |
| **infra** | 6+ | Infrastructure setup |
| **common** | 15+ | Shared utilities |
| **version** | 3 | Semantic versioning |
| **Total** | 40+ | Complete action suite |

---

## 🎯 How Actions Work Together

### Deployment Flow

```
User calls main aggregator
    ↓
route-category determines category
    ↓
Appropriate dispatcher called (e.g., app/dispatch)
    ↓
Dispatcher calls specific action (e.g., ssh-django-deploy)
    ↓
Action executes (may call other actions)
    ↓
operation-summary prints results
```

### Example: Django Deployment

```
1. build-and-push
   - Builds Docker image
   - Pushes to registry
   - Outputs: env_name, image_tag, deploy_enabled

2. ssh-django-deploy
   - prepare-ubuntu-host (optional)
   - write-remote-env-file (optional)
   - podman-login-pull
   - remote-podman-exec (run migrations)
   - podman-run-service (start container)

3. operation-summary
   - Prints deployment results
```

---

## 📚 Finding Action Documentation

Each action has its own README:

- `.github/actions/app/ssh-django-deploy/README.md`
- `.github/actions/build/build-and-push/README.md`
- `.github/actions/infra/prepare-ubuntu-host/README.md`
- And more...

**To find action documentation**:
1. Navigate to `.github/actions/<category>/<action-name>/`
2. Look for `README.md`
3. Check for inline comments in `action.yml`

---

## 🔗 Cross-References

### Related Documentation

- **ARCHITECTURE.md** - How actions are organized
- **VARIABLES_REFERENCE.md** - All parameters for each action
- **GETTING_STARTED.md** - How to use actions
- **DOCUMENTATION_INDEX.md** - Find anything

### Finding Specific Actions

**By purpose**:
- Deploy Django → `ssh-django-deploy`
- Deploy Next.js → `ssh-nextjs-deploy`
- Build image → `build-and-push`
- Setup server → `prepare-ubuntu-host`

**By category**:
- See ARCHITECTURE.md - Categories section

**By parameter**:
- See VARIABLES_REFERENCE.md

---

## ✨ Key Takeaways

- **37+ action files** organized into 6 categories
- **User-facing actions** for deployment and building
- **Internal utilities** for routing and validation
- **Dispatcher pattern** for flexible routing
- **Modular design** allows reuse and composition
- **Each action documented** with README and comments

---

**Start exploring**: Pick an action that matches your need and read its README!
