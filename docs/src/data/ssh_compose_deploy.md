# SSH Compose Deploy

The `ssh-compose-deploy` subaction deploys a Compose project on a remote host over SSH using Podman Compose (or `podman-compose` fallback).

## When to use it

Use this subaction when your remote server already has a Compose project structure (services, volumes, mounts, and runtime config) and you want to deploy by reconciling that project in place.

## What it does

1. Validates required SSH inputs and `app_slug`.
2. Optionally writes a remote `.env` file from `env_b64` or `env_content`.
3. Resolves project paths (supports absolute and `~/`-relative inputs).
4. Verifies required files before deploy (`docker-compose.yml`, env file, and optional host files).
5. Optionally logs in to your registry.
6. Runs `compose pull` (default) and `compose up -d --remove-orphans` remotely.

## Usage

Provide deployment inputs in `params_json`:

```yaml
- name: Deploy Compose Project
  uses: uncoverthefuture-org/actions@master
  with:
    subaction: ssh-compose-deploy
    secrets_json: ${{ toJSON(secrets) }}
    params_json: |
      {
        "ssh_host": "${{ secrets.SERVER_IP }}",
        "ssh_user": "${{ secrets.SSH_USERNAME }}",
        "ssh_key": "${{ secrets.SSH_PRIVATE_KEY }}",
        "app_slug": "shako-laravel-api",
        "env_name": "development",
        "compose_project_dir": "~/deployments/development/shako-laravel-api",
        "compose_file_path": "docker-compose.yml",
        "compose_env_file_path": ".env",
        "required_host_files": "/opt/secrets/firebase-service-account.json",
        "compose_pull": "true",
        "debug": "true"
      }
```

## Common parameters

- `ssh_host`, `ssh_user`, `ssh_key`: Required SSH connection fields.
- `app_slug`: Required for deriving default deployment paths.
- `deployment_base_dir`: Base directory for default project path resolution.
- `compose_project_dir`: Compose project directory on remote host.
- `compose_file_path`: Compose file path (absolute or relative to project dir).
- `compose_env_file_path`: Compose env file path (absolute or relative to project dir).
- `required_host_files`: Newline-separated absolute file paths that must exist on host.
- `compose_pull`: Whether to pull images before `up` (`true` by default).
- `compose_up_args`: Extra flags appended to `compose up`.
- `registry`, `registry_username`, `registry_token`, `registry_login`: Optional registry auth.
- `version` / `image_tag`: Exported as `IMAGE_TAG` for Compose interpolation.

## Notes

- The subaction fails fast if project directory, compose file, or env file is missing.
- `required_host_files` entries must be absolute paths.
- The action supports both `podman compose` and `podman-compose` on the remote host.
