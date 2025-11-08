# build-and-push

Build and push a container image to a registry. Determines environment context (env_name, image_tag, deploy_enabled) from a script or auto-fallback.

## Inputs
- `image_name` (required), `registry?=ghcr.io`, `github_token` (required)
- `environment_script?` (defaults to `.github/scripts/set-environment-context.sh` if present)

## Outputs
- `env_name`, `env_key`, `image_tag`, `deploy_enabled`

## Example (via root aggregator)
```yaml
- id: build
  uses: uncoverthefuture-org/actions@master
  with:
    subaction: build-and-push
    params_json: |
      {
        "image_name": "${{ github.repository }}",
        "registry":   "ghcr.io",
        "github_token": "${{ secrets.GITHUB_TOKEN }}"
      }
```
- You will need `permissions: packages: write` for GHCR.

---

## Build-time environment (secrets) support

This action now supports passing your environment file to the Docker build as a BuildKit secret. The env is used during image build but is not baked into layers.

What happens in CI:
- The action resolves the current environment (production/staging/development).
- It decodes the matching base64 secret (e.g., `PROD_ENV_B64`, `STAGING_ENV_B64`, `DEV_ENV_B64`) into a temporary `.env` file in the runner workspace.
- It passes the file to `docker/build-push-action` via `secrets: id=app_env,src=/abs/path/to/.env`.
- Your Dockerfile can consume it during `RUN` steps using BuildKit’s secret mount.

The secret is ephemeral and never persisted as an image layer.

### Dockerfile usage

Add the modern BuildKit syntax line and mount the secret where needed.

Node example (tolerant when secret is not provided locally):

```Dockerfile
# syntax=docker/dockerfile:1.7
FROM node:20 AS build
RUN --mount=type=secret,id=app_env bash -c 'f=/run/secrets/app_env; if [ -f "$f" ]; then set -a; . "$f"; set +a; fi; npm ci && npm run build'
```

Python example:

```Dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS build
RUN --mount=type=secret,id=app_env bash -c 'f=/run/secrets/app_env; if [ -f "$f" ]; then set -a; . "$f"; set +a; fi; pip install -r requirements.txt'
```

If you want the build to fail when the secret is missing, add `required=true` to the `--mount`:

```Dockerfile
RUN --mount=type=secret,id=app_env,required=true bash -c 'set -a; . /run/secrets/app_env; set +a; <build-cmd>'
```

### Local builds

You have two approaches:

- Pass your local `.env` as a BuildKit secret (recommended):
  - Docker (BuildKit):
    - `DOCKER_BUILDKIT=1 docker build --secret id=app_env,src=.env -t myapp:dev .`
  - Buildx:
    - `docker buildx build --secret id=app_env,src=.env -t myapp:dev .`
  - Docker Compose v2:
    ```yaml
    services:
      app:
        build:
          context: .
          secrets:
            - source: app_env
              id: app_env
    secrets:
      app_env:
        file: .env
    ```
    - Then: `docker compose build`

- Or make your Dockerfile tolerant (as shown above) so builds succeed even when you don’t provide a secret locally.

### Security notes

- Build-time env is provided as a BuildKit secret and is not committed to image layers.
- Avoid copying `.env` into the image or using `ARG` to pass sensitive data.
- Runtime remains separate: deployment passes the `.env` to `podman run` via `--env-file`.

### Troubleshooting

- “Unknown flag: --mount” or secret not available: ensure the Dockerfile has `# syntax=docker/dockerfile:1.7` (or newer) and BuildKit is enabled.
- “Secret file not found”: either pass the secret in your local build command or remove `required=true` from the `--mount` and guard with `[ -f ]` checks.
- Compose: ensure you use Docker Compose v2 and put build secrets under `build.secrets` (as shown above), plus define the top-level `secrets` source.
