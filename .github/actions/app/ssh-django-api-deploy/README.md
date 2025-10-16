# ssh-django-api-deploy

Deploy a Django API to a remote Linux host over SSH. Optionally prepares the host, writes a .env file, logs into a registry, pulls the image, runs the container, and manages an Apache vhost.

- **Derived defaults**
  - `app_slug` = slugified `${{ github.repository }}` name
  - `env_dir_path` = `/opt/<app_slug>`
  - `env_file_path` = `/opt/<app_slug>/.env.`
  - `image_name` = `<owner>/<repo>`

## Inputs (most relevant)
- **SSH**: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?=22`, `ssh_fingerprint?`
- **Env**: `env_name` (required), `env_file_path?`, `write_env_file?`, `env_b64?` or `env_content?`
- **Registry**: `registry=ghcr.io`, `registry_login?=true`, `registry_username?`, `registry_token?`, `image_name?`, `image_tag` (required)
- **Runtime**: `container_name?`, `host_port?`, `container_port?`, `restart_policy?`, `extra_run_args?`, `memory_limit?`
- **VHost (optional)**: `manage_vhost?`, `domain?` or `base_domain` + `env_name` + prefixes (`domain_prefix_prod`, `domain_prefix_staging`, `domain_prefix_dev`), `vhost_mode?`, `wsgi_script_path?`

## Example (via root aggregator)
```yaml
- uses: uncoverthefuture-org/actions@v1
  with:
    subaction: ssh-django-api-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "root_ssh_key": "${{ secrets.ROOT_SSH_KEY }}",
        "env_name": "production",
        "registry": "ghcr.io",
        "image_tag": "${{ needs.build.outputs.image_tag }}",
        "registry_login": "true",
        "registry_username": "${{ secrets.GHCR_USERNAME }}",
        "registry_token": "${{ secrets.GHCR_TOKEN }}",
        "manage_vhost": "true",
        "base_domain": "posteat.co.uk",
        "domain_prefix_prod": "django-api",
        "domain_prefix_staging": "django-api-staging",
        "domain_prefix_dev": "django-api-dev"
      }
```
