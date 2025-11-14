# SSH Container Deploy

Deploy a generic containerized app to a remote server via SSH using Podman. Supports Traefik routing by default when a domain is available, and falls back to host port mapping otherwise.

## Minimal usage (GitHub Actions)

```yaml
- name: Deploy Container
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: ssh-container-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SERVER_HOST }}",
        "ssh_key":  "${{ secrets.SERVER_SSH_KEY }}",
        "enable_traefik": "true",
        "base_domain": "${{ secrets.BASE_DOMAIN }}",
        "env_name": "production",
        "write_env_file": "true",
        "env_b64": "${{ secrets.PROD_ENV_B64 }}"
      }
```

Notes:
- When `enable_traefik` is `true`, the action will probe the server for Traefik and automatically run host preparation if it is missing.
- If no domain/base_domain is provided, the action publishes a host port (see port mapping below).

## base_domain vs explicit domain

- `domain` (explicit): Provide a full FQDN (e.g., `app.example.com`). The action will use this exact host for Traefik labels.
- `base_domain` (derived): Provide an apex domain (e.g., `example.com`). The action derives the FQDN by environment:
  - production: `domain_prefix_prod` + `base_domain` (default prefix is empty, so apex is used; e.g., `example.com`)
  - staging: `domain_prefix_staging` + `base_domain` (default: `staging.example.com`)
  - development: `domain_prefix_dev` + `base_domain` (default: `dev.example.com`)

You can override prefixes via inputs:
- `domain_prefix_prod` (default: empty string)
- `domain_prefix_staging` (default: `staging`)
- `domain_prefix_dev` (default: `dev`)

## Port selection and fallbacks (remote .env)

The action determines ports in this order:

- Host port (`HOST_PORT`):
  1) `host_port` input
  2) `WEB_HOST_PORT` from remote `.env`
  3) `PORT` from remote `.env`
  4) Default: `8080` (persisted per app/env; auto-increments if occupied)

- Container port (`CONTAINER_PORT`):
  1) `container_port` input
  2) `WEB_CONTAINER_PORT` from remote `.env`
  3) `TARGET_PORT` from remote `.env`
  4) `PORT` from remote `.env`
  5) Default: `8080` (project standard; override if your app listens elsewhere)

When Traefik is enabled and a domain is available, the action does not publish host ports (`-p`). Instead, it attaches Traefik labels and sets the service port to `CONTAINER_PORT`.

## Remote .env location

By default, the env file is stored on the server at:

```
/var/deployments/<env>/<app_slug>/.env
```

- `<env>` is derived from branch or `env_name` (production|staging|development)
- `<app_slug>` is derived from the repository name (lowercased, slugified)

You can upload the env via base64 payload:
- `write_env_file: true`
- `env_b64: ${{ secrets.PROD_ENV_B64 }}` (or `STAGING_ENV_B64`, `DEV_ENV_B64`)

## Traefik fast-path and ensure_traefik

- `ensure_traefik` (default `'true'`) gates all Traefik-related checks and reconciliation in this action.
  - When set to `'false'`, the action skips Traefik preflight checks, the `infra/setup-traefik` reconciliation step, and the post-deploy routing probe. App deployment still proceeds normally.
- Fast-path: `infra/setup-traefik` probes first and is a no-op when Traefik is already running, ports 80/443 are listening, and the configuration is up-to-date. Upload and setup are only performed when needed or when `force_restart: 'true'` is passed to that action.

Example usage (skip Traefik entirely, useful if Traefik is managed out-of-band):

```yaml
- name: Deploy Container
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: ssh-container-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SERVER_HOST }}",
        "ssh_user": "${{ secrets.SERVER_USER }}",
        "ssh_key":  "${{ secrets.SERVER_SSH_KEY }}",
        "enable_traefik": "true",
        "ensure_traefik": "false",
        "base_domain": "${{ secrets.BASE_DOMAIN }}",
        "env_name": "production"
      }
```

## Additional tips

- If `enable_traefik` is `true` and Traefik is not detected, host preparation will run automatically. You can optionally set `ufw_allow_ports: "80 443"` to open HTTP/HTTPS.
- To force a specific container name, set `container_name`. Otherwise it defaults to `<app_slug>-<env>`.
- Use `extra_run_args` to pass additional Podman flags (e.g., volumes).

## SSH reachability failures

This action performs a lightweight SSH probe before any remote work:

- When the probe **succeeds**, deployment proceeds normally.
- When the probe **fails** (host offline, DNS issue, port blocked, bad key),
  the action now fails fast with a clear error instead of reporting a
  successful deployment in the operation summary.

Example (simplified workflow excerpt):

```yaml
- name: Deploy Container
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: ssh-container-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SERVER_HOST }}",
        "ssh_user": "${{ secrets.SERVER_USER }}",
        "ssh_key":  "${{ secrets.SERVER_SSH_KEY }}",
        "base_domain": "example.com"
      }
```

If the host is unreachable, the logs will contain an error like:

```text
::error title=SSH host unreachable::SSH host 'example.com' is unreachable after 3 attempt(s) on port 22.
Last SSH error message:
ssh: connect to host example.com port 22: Connection timed out
```

and the overall Uncover operation summary will show the app deployment as
failed instead of "✅ Success".
