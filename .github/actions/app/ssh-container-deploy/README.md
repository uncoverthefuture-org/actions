# SSH Container Deploy

Deploy a generic containerized app to a remote server via SSH using Podman.

This is the **default deploy path** for new projects:

- Uses a single composite action to handle host preparation (optional), env file upload, image pull, and container run.
- Prefers Traefik routing when a domain is available, and falls back to host-port mapping when no domain is provided.

## What this action does

At a high level this action:

1. Validates SSH connectivity to your server.
2. Optionally prepares the host (Podman, Traefik, directories) when needed.
3. Writes or updates a remote `.env` file for your app.
4. Logs in to your container registry (optional) and pulls the image.
5. Starts or replaces the app container:
   - With Traefik labels when a domain is available.
   - Or with `-p host:container` ports when no domain is available.

Behind the scenes it also prepares a per-environment deployment directory under `~/deployments/{env_name}/{app_slug}` on the remote host. When passwordless `sudo` is available, the scripts normalize ownership of this directory (and existing files within it) to the SSH user so that files created there can be read and updated without manual `chown`/`chmod` fixes between deploys.

## When to use this action

Use `ssh-container-deploy` when you want to:

- Deploy any containerized web/API app to a Linux server via SSH.
- Reuse the same deployment flow for production, staging, and development.
- Prefer Traefik-based HTTPS routing when a domain exists, with a clean host-port fallback.

Older app-specific deployers (Django, Laravel, etc.) are still available for legacy workflows, but new projects should use this generic action whenever possible.

## Minimal usage (GitHub Actions)

This example deploys a production app using Traefik and a base64-encoded `.env` secret:

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
        "base_domain": "${{ secrets.BASE_DOMAIN }}",
        "env_name": "production",
        "write_env_file": "true",
        "env_b64": "${{ secrets.PROD_ENV_B64 }}"
      }
```

Notes:
- When `enable_traefik` is `true`, the action will probe the server for Traefik and automatically run host preparation if it is missing.
- If no `domain`/`base_domain` is provided, the action publishes a host port instead (see port mapping below).
 
## Inputs

All inputs are provided via the `params_json` object. The tables below list each input, its default, and what it controls.

### SSH & connectivity

| Input | Default | Description |
|-------|---------|-------------|
| `ssh_host` | – | Required. SSH host (IP or DNS) of the remote server. |
| `ssh_user` | – | Required. SSH username used for remote execution. |
| `ssh_key` | – | Required. Private key for `ssh_user` (PEM, usually from a secret). |
| `root_ssh_key` | – | Optional key for root when privileged operations are needed. |
| `ssh_port` | `22` | SSH port on the remote host. |
| `ssh_fingerprint` | – | Optional host key fingerprint for trust pinning. |
| `skip_upload` | `true` | Skip staging `deploy-container.sh` when scripts are already present. |
| `ensure_scripts_deployed` | `true` | Automatically deploy/update the server scripts bundle before remote steps. |

### Host preparation & infra

| Input | Default | Description |
|-------|---------|-------------|
| `prepare_host` | `true` | Run first-time host prep (install Podman/Traefik, create directories). |
| `install_podman` | `true` | Install Podman during host prep if missing. |
| `create_podman_user` | `false` | Create the `podman_user` account when it does not exist. |
| `install_traefik` | `true` | Install or reconcile Traefik during host prep. |
| `traefik_email` | – | Email passed to Traefik ACME for certificate registration. |
| `env_dir_path` | – | Base directory for env files and app metadata (overrides default). |
| `deployment_base_dir` | `~/deployments` | Base directory for per-env app deployment roots. |
| `additional_packages` | `jq curl ca-certificates` | Extra apt packages installed during host prep. |
| `ufw_allow_ports` | `''` | Space-separated ports to open in UFW (e.g. `"80 443"`). |
| `install_webmin` | `true` | Install Webmin during host prep (requires sudo). |
| `install_usermin` | `false` | Install Usermin alongside Webmin. |
| `install_portainer` | `true` | Install Portainer CE as a Quadlet-managed service on the host. When enabled, the deploy flow ensures a persistent Portainer container exists. |
| `portainer_https_port` | `9443` | Direct HTTPS port for Portainer UI on the host (e.g. `https://server:9443`). |
| `portainer_domain` | `''` | Optional FQDN to expose Portainer via Traefik (e.g. `portainer.example.com` → `https://portainer.example.com`). When omitted and an app domain is configured, the deploy scripts derive a default of the form `portainer.<apex>`, for example `dev.shakohub.com` → `portainer.shakohub.com`. |
| `show_root_install_hints` | `true` | Print manual instructions when root privileges are required. |

### Environment & app metadata

| Input | Default | Description |
|-------|---------|-------------|
| `env_name` | – | Logical env name (`production`, `staging`, `development`). Auto-derived when omitted. |
| `auto_detect_env` | `true` | Derive `env_name` from branch/tag via `compute-defaults`. |
| `env_file_path` | – | Base path for `.env` on the host (otherwise derived from `deployment_base_dir`). |
| `write_env_file` | `false` | When true, write `env_b64`/`env_content` to the remote `.env`. |
| `env_b64` | – | Base64-encoded `.env` payload to materialize on the host. |
| `env_content` | – | Raw `.env` content (prefer `env_b64` for secrets). |
| `auto_fetch_env` | `true` | Resolve `env_b64` automatically from job env (e.g. `PROD_ENV_B64`). |
| `env_secret_prefix` | `''` | Prefix used when deriving env secret var names from `env_name`. |
| `env_secret_suffix` | `_ENV_B64` | Suffix used when deriving env secret var names from `env_name`. |
| `app_slug` | – | Human-readable app slug; defaults from repo name when omitted. |
| `container_name` | – | Override Podman container name (default: `<app_slug>-<env>`). |

### Registry & image

| Input | Default | Description |
|-------|---------|-------------|
| `registry` | `ghcr.io` | Container registry hostname for image pulls. |
| `image_name` | – | Image path without tag (e.g. `org/app`). |
| `image_tag` | – | Tag to deploy (e.g. `production-abcdef`). |
| `registry_username` | – | Registry username (defaults from GitHub actor for `ghcr.io`). |
| `registry_token` | – | Registry password/token. |
| `registry_login` | `true` | Attempt registry login before pulling when credentials exist. |

### Runtime & ports

| Input | Default | Description |
|-------|---------|-------------|
| `host_port` | – | Host port to publish when Traefik is disabled. |
| `container_port` | – | Container service port (labels/port mapping). Defaults from `.env` or `default_container_port`. |
| `default_host_port` | `8080` | Fallback host port when Traefik is disabled and `host_port` is empty. |
| `default_container_port` | `8080` | Fallback container port when `container_port` is empty. |
| `restart_policy` | `unless-stopped` | Podman restart policy for the app container. |
| `extra_run_args` | – | Extra flags appended to `podman run` (e.g. extra volumes, caps). |
| `memory_limit` | `512m` | Memory (and swap) limit applied to the container. |

### Traefik, domains & TLS

| Input | Default | Description |
|-------|---------|-------------|
| `enable_traefik` | `true` | Attach Traefik labels and network when a domain is provided. When `true` and a domain is present, the action prefers Traefik-based HTTPS routing over direct host ports. |
| `ensure_traefik` | `true` | Run Traefik preflight + reconciliation **on the host** via the `ensure-traefik-ready.sh` script when `enable_traefik=true`. Set to `false` when Traefik is fully managed out-of-band and you do not want the deploy flow to touch it. Quadlet-based Traefik can still be installed separately using the `infra/setup-traefik` composite in your workflows. |
| `enable_acme` | `true` | Attach certresolver labels so Traefik requests Let’s Encrypt certs. |
| `traefik_reset_acme` | `false` | When `true`, reset ACME storage (`acme.json`) on next run to force new certs. |
| `traefik_network_name` | `traefik-network` | Podman network for Traefik and app containers. |
| `traefik_use_host_network` | `false` | Run Traefik on host network to avoid CNI DNS issues. |
| `traefik_skip_upload` | `true` | Skip uploading Traefik scripts when already installed. |
| `enable_dashboard` | `true` | Enable Traefik dashboard exposure (when paired with `dashboard_publish_modes`). |
| `dashboard_publish_modes` | `''` | CSV: `http8080`, `https8080`, `subdomain`, or `both`. |
| `dashboard_host` | `''` | FQDN for dashboard when using `subdomain` mode. |
| `dashboard_password` | `''` | Plain dashboard password (hashed on host); default user is `admin`. |
| `dashboard_users_b64` | `''` | Base64 htpasswd users file; overrides `dashboard_password`. |

### Podman storage cleanup

| Input | Default | Description |
|-------|---------|-------------|
| `enable_podman_cleanup` | `true` | When `true`, run a safe Podman storage cleanup **after** a successful deployment. This invokes `infra/prune-podman-storage.sh` on the host to prune stopped containers and unused images using an age-based filter, helping prevent overlay storage from growing without bound. |
| `podman_cleanup_min_age_days` | `15` | Minimum age (in days) before Podman containers/images become eligible for pruning. Resources newer than this threshold are never removed by the cleanup step. |
| `podman_cleanup_keep_recent_images` | `2` | Hint for how many recent images to keep per host. Currently used for logging alongside the age-based prune, which already preserves recent and in-use images. |

| `dns_servers` | `''` | Optional DNS servers for the Traefik container (`--dns`). |
| `domain` | `''` | Explicit FQDN for the app (e.g. `app.example.com`). |
| `base_domain` | `''` | Apex domain used to derive env-specific hosts (e.g. `example.com`). |
| `domain_prefix_prod` | `''` | Prefix for production when `base_domain` is set (default: apex only). |
| `domain_prefix_staging` | – | Prefix for staging when `base_domain` is set (e.g. `staging`). |
| `domain_prefix_dev` | – | Prefix for development when `base_domain` is set (e.g. `dev`). |
| `require_dns_match` | `true` | Reserved flag to gate changes behind DNS validation. |
| `domain_aliases` | `''` | Comma/space-separated aliases routed to the service. |
| `include_www_alias` | `false` | When true and `domain` is set, also include `www.<domain>` as alias. |
| `domain_hosts` | `''` | CSV of hostnames to route (overrides `domain_aliases` when set). |
| `probe_path` | `/` | Path used by the Traefik probe to validate readiness (e.g. `/health`). |

### Diagnostics & summary

| Input | Default | Description |
|-------|---------|-------------|
| `debug` | `false` | Enable verbose logging for troubleshooting. |
| `summary_mode` | `full` | Controls operation summary: `full`, `light`, or `off`. |
| `source_env` | `true` | Source the remote `.env` before running deployment scripts. |
| `fail_if_env_missing` | `true` | When `source_env=true`, fail if the `.env` file cannot be sourced. |

### Portainer & Traefik credential storage

Portainer and the Traefik dashboard both rely on **server-side state** for credentials. The deploy flow does **not** print any admin passwords into GitHub logs; instead it uses on-host files and in-app configuration.

- **Portainer data directory**

  When `install_portainer=true`, Portainer stores its state (including the admin user and password hash) under:

  ```text
  $HOME/.local/share/portainer
  ```

  The `install-portainer.sh` script surfaces this path in the remote logs as the **Portainer data directory**. Treat this directory as **secret** on the server. Portainer will prompt for an admin account on first login; choose a strong password and rotate it via the UI when needed.

- **Traefik dashboard users file**

  When the Traefik dashboard is enabled (`enable_dashboard=true` or `dashboard_publish_modes` non-empty), the setup scripts create a basic auth users file on the host, for example:

  ```text
  /etc/traefik/dashboard-users             # when sudo available
  $HOME/.config/traefik/dashboard-users   # otherwise
  ```

  The path is printed in the Traefik setup logs as the **dashboard users file** and should be treated as secret, since it contains hashed credentials.

  If you do **not** provide `dashboard_password` or `dashboard_users_b64`, the dashboard falls back to a **bootstrap default** of `admin/12345678`. This default is written only into the users file above and is never echoed in plain text to logs.

  You must change the dashboard credentials immediately by either:

  - Setting `dashboard_password` in your workflow (the action will hash it on the host), or
  - Supplying a precomputed htpasswd file via `dashboard_users_b64`.

  **Example (custom dashboard password)**

  ```jsonc
  // ...base params_json omitted...
  "enable_traefik": "true",
  "enable_dashboard": "true",
  "dashboard_publish_modes": "subdomain",
  "dashboard_host": "traefik.example.com",
  "dashboard_password": "changeMeNow123!"
  ```

  On the first run, the scripts will hash `changeMeNow123!`, write it to the users file, and route `https://traefik.example.com` to Traefik’s dashboard protected by basic auth.

## Examples

These examples build on the **Minimal usage** snippet above. Only the relevant extra fields are shown.

### Skip Traefik reconciliation (Traefik managed out-of-band)

Add to your `params_json`:

```jsonc
// ...base params_json omitted for brevity...
"ensure_traefik": "false"
```

### Rotate TLS certificate (reset ACME storage once)

If the logs show a staging or otherwise untrusted certificate, you can trigger an ACME reset on a one-off run:

```jsonc
// ...base params_json omitted for brevity...
"traefik_reset_acme": "true"
```

When `ensure_traefik` is `false`, the action still attaches Traefik labels (when `enable_traefik=true`) but **does not** run the Quadlet/setup-traefik flow or the host-side `ensure-traefik-ready.sh`; this is useful when an operations team manages Traefik separately.

The post-deploy probe will also log TLS certificate issuer/subject/validity so you can confirm when a trusted Let’s Encrypt production certificate is in use.

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
