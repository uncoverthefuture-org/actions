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
