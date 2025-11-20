# DOCTL Container Deploy

Deploy a generic containerized app to a **DigitalOcean Droplet** using:

- `digitalocean/action-doctl` to install and authenticate `doctl`
- `doctl compute ssh` to reach the Droplet
- The same **server-managed scripts bundle** used by `ssh-container-deploy`:
  - `scripts/app/start-container-deployment.sh`
  - `scripts/app/run-deployment.sh`
  - `scripts/app/deploy-container.sh`

This means **all deployment behavior is identical** to `ssh-container-deploy` once on the host (Traefik, UFW, Webmin, env file handling, registry login, etc.), but the transport is DigitalOcean’s CLI instead of a stand‑alone SSH action.

## When to use this action

Use `doctl-container-deploy` when:

- Your app runs on a DigitalOcean Droplet
- You want to authenticate using a **DigitalOcean API token** + `doctl`
- You still have an SSH key on the Droplet, but prefer doctl to own the connection
- You already rely on the uactions scripts bundle (`~/uactions/scripts`) for deploys

For non-DigitalOcean servers (bare VPS, on‑prem), keep using `ssh-container-deploy`.

## Minimal usage via aggregator

Example workflow step using the main `uncoverthefuture-org/actions` aggregator:

```yaml
- name: Deploy to DigitalOcean via doctl
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: doctl-container-deploy
    params_json: |
      {
        "do_token": "${{ secrets.DO_API_TOKEN }}",
        "ssh_host": "my-app-prod",                // Droplet name or ID
        "ssh_user": "root",                      // or deploy
        "ssh_key":  "${{ secrets.DROPLET_SSH_KEY }}",

        "enable_traefik": "true",
        "base_domain": "${{ secrets.BASE_DOMAIN }}",
        "env_name": "production",
        "write_env_file": "true",
        "env_b64": "${{ secrets.PROD_ENV_B64 }}"
      }
```

**What this does:**

1. Installs and authenticates `doctl` using `secrets.DO_API_TOKEN`.
2. Computes defaults for `env_name`, `image_name`, `image_tag`, and domain.
3. Validates inputs (registry, env payload, Traefik email/domain).
4. Bundles `./.github/actions/scripts` into `uactions-scripts.tgz`.
5. Uploads the tarball to the Droplet via `doctl compute ssh`.
6. Extracts the bundle into `~/uactions/scripts` on the Droplet.
7. Runs `start-container-deployment.sh`, which:
   - Ensures Podman exists
   - Manages env file and deployment directory
   - Optionally configures UFW + Webmin
   - Ensures Traefik is ready (idempotent)
   - Runs `deploy-container.sh` with Traefik or port mappings

## Required inputs

All inputs are passed through via `params_json`. The most important ones for a basic deploy are:

| Input         | Required | Description |
|--------------|----------|-------------|
| `do_token`   | ✅       | DigitalOcean API token (repo/org secret) used by `digitalocean/action-doctl`. |
| `ssh_host`   | ✅       | Droplet identifier for `doctl compute ssh` (name or ID). |
| `ssh_user`   | ✅       | SSH user on the Droplet (default `root`). |
| `ssh_key`    | ✅       | Private SSH key for `ssh_user` in PEM format (secret). |
| `env_name`   | ➖       | Logical env name; auto‑derived from branch when omitted. |
| `env_b64`    | ➖       | Base64 `.env` content; can be auto‑resolved from `PROD_ENV_B64`/`STAGING_ENV_B64`/`DEV_ENV_B64`. |
| `image_name` | ➖       | Image repo (`org/app`); defaults from `owner/repo` when omitted. |
| `image_tag`  | ➖       | Image tag; defaults to `<env>-<sha7>` when omitted. |
| `base_domain`/`domain` | ➖ | Domain routing through Traefik; falls back to host port mapping when absent. |

The rest of the inputs mirror `ssh-container-deploy` (ports, Traefik flags, dashboard options, UFW, Webmin, etc.) and are forwarded directly to the server scripts.

## Example: simple host-port deployment (no Traefik)

```yaml
- name: Deploy API to Droplet (no Traefik)
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: doctl-container-deploy
    params_json: |
      {
        "do_token": "${{ secrets.DO_API_TOKEN }}",
        "ssh_host": "my-api-dev",
        "ssh_user": "root",
        "ssh_key":  "${{ secrets.DROPLET_SSH_KEY }}",

        "enable_traefik": "false",
        "env_name": "development",
        "write_env_file": "true",
        "env_b64": "${{ secrets.DEV_ENV_B64 }}",

        "host_port": "8080",
        "container_port": "3000"
      }
```

This deploys your container to the Droplet and exposes it on `http://<droplet-ip>:8080` without Traefik, while still using the same Podman + UFW + env file behavior as the SSH-based action.
