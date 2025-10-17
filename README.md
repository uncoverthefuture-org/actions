# actions
All actions we will ever need in this life for tech

## Build and Push Docker Image

This action builds and pushes a Docker image for a Django API, determining the environment context.

### Inputs

- `registry`: Docker registry to use (default: `ghcr.io`)
- `image_name`: Name of the Docker image (required)
- `github_token`: GitHub token for authentication (required)
- `environment_script`: Path to the script that sets environment context (default: `.github/scripts/set-environment-context.sh`)

### Outputs

- `env_name`: Environment name
- `env_key`: Environment key
- `image_tag`: Image tag
- `deploy_enabled`: Whether deployment is enabled

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/build-and-push@master
  with:
    image_name: ${{ github.repository_owner }}/my-app
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

Note: Your workflow must grant `permissions: packages: write` for GHCR.

## Remote Podman Exec

Generic SSH runner that exposes a `run_podman` helper and supports root vs user execution.

### Inputs

- `ssh_host` (required)
- `ssh_user` (required)
- `ssh_key` (required)
- `root_ssh_key` (optional)
- `podman_user` (default: `deployer`)
- `connect_mode` (`auto`|`root`|`user`, default: `auto`)
- `env_file_path` (default: derived from repo slug, e.g. `/opt/<repo-slug>/.env.`)
- `env_name` (optional)
- `source_env` (default: `false`)
- `fail_if_env_missing` (default: `true`)
- `inline_script` (required)

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/remote-podman-exec@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    podman_user: deployer
    connect_mode: auto
    env_name: staging
    source_env: true
    inline_script: |
      run_podman --version
```

## Prepare Ubuntu Host

Prepares a fresh Ubuntu host for rootless Podman deployments.

### Inputs

- `ssh_host`, `ssh_user`, `ssh_key` (required)
- `root_ssh_key` (optional)
- `connect_mode` (default: `root`)
- `podman_user` (default: `deployer`)
- `create_podman_user` (default: `false`)
- `env_dir_path` (default: derived from repo slug, e.g. `/opt/<repo-slug>`)
- `install_podman` (default: `true`)
- `additional_packages` (default: `jq curl ca-certificates`)

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/prepare-ubuntu-host@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    root_ssh_key: ${{ secrets.ROOT_SSH_KEY }}
    podman_user: deployer
    create_podman_user: true
```

## SSH Django API Deploy

Optionally prepares the host, writes an env file, and deploys a Django API container via Podman.

### Inputs (highlights)

- `ssh_host`, `ssh_user`, `ssh_key`, `env_name`, `image_name`, `image_tag` (required)
- `registry_username`, `registry_token` (required when `registry_login: true`)
- `prepare_host` (default: `false`)
- `write_env_file` (default: `false`), `env_b64` or `env_content`
- `registry` (default: `ghcr.io`)
- `podman_user` (default: `deployer`), `connect_mode` (default: `auto`)
- `migrate` (default: `true`), `migrate_cmd` (default: `python manage.py migrate --noinput`)
- `host_port`, `container_port`, `restart_policy` (default: `unless-stopped`)

### Usage: full setup on a fresh server

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/ssh-django-api-deploy@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    root_ssh_key: ${{ secrets.ROOT_SSH_KEY }}
    podman_user: deployer
    prepare_host: true
    create_podman_user: true
    env_name: production
    write_env_file: true
    env_b64: ${{ secrets.PROD_ENV_B64 }}
    registry_username: ${{ secrets.GHCR_USERNAME }}
    registry_token: ${{ secrets.GHCR_TOKEN }}
    registry: ghcr.io
    image_name: ${{ github.repository_owner }}/ekaban-django-api
    image_tag: v1.2.3
```

### Usage: deploy only (host already prepared)

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/ssh-django-api-deploy@main
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    env_name: staging
    registry_username: ${{ secrets.GHCR_USERNAME }}
    registry_token: ${{ secrets.GHCR_TOKEN }}
    image_name: ${{ github.repository_owner }}/ekaban-django-api
    image_tag: ${{ needs.build.outputs.image_tag }}
```

## Write Remote Env File

Writes a `.env` file to the remote host.

### Inputs

- `ssh_host`, `ssh_user`, `ssh_key`, `env_name` (required)
- `root_ssh_key` (optional)
- `ssh_port` (default: `22`), `ssh_fingerprint` (optional)
- `env_file_path` (default: derived from repo slug, e.g. `/opt/<repo-slug>/.env.`)
- `env_b64` or `env_content` (one required)
- `podman_user` (default: `deployer`), `connect_mode` (default: `auto`)

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/write-remote-env-file@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    env_name: production
    env_b64: ${{ secrets.PROD_ENV_B64 }}
```

## Podman Login and Pull

Securely logs in to the registry using `--password-stdin` and pulls the image.

### Inputs

- `ssh_host`, `ssh_user`, `ssh_key` (required)
- `registry`, `image_name`, `image_tag` (required)
- `registry_login` (default: `true`), and when `true` also require `registry_username`, `registry_token`
- `root_ssh_key` (optional)
- `ssh_port` (default: `22`), `ssh_fingerprint` (optional)
- `podman_user` (default: `deployer`), `connect_mode` (default: `auto`)

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/podman-login-pull@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    registry: ghcr.io
    registry_login: true
    registry_username: ${{ secrets.GHCR_USERNAME }}
    registry_token: ${{ secrets.GHCR_TOKEN }}
    image_name: ${{ github.repository_owner }}/ekaban-django-api
    image_tag: v1.2.3
```

## Podman Stop and Remove Container

Stops and removes a container by name on the remote host.

### Inputs

- `ssh_host`, `ssh_user`, `ssh_key` (required)
- `container_name` or provide `app_slug` and `env_name`
- `root_ssh_key` (optional)
- `ssh_port` (default: `22`), `ssh_fingerprint` (optional)
- `podman_user` (default: `deployer`), `connect_mode` (default: `auto`)

### Usage

```yaml
- uses: uncoverthefuture-org/actions/.github/actions/podman-stop-rm-container@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key: ${{ secrets.SSH_KEY }}
    app_slug: ekaban-api
    env_name: production
```
