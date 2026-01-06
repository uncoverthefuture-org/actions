# SSH Container Deploy

A composite GitHub Action that deploys containerized applications via SSH using Podman. It supports:
- Automated host preparation (Podman, Traefik, UFW, directories)
- Remote environment file management
- Zero-downtime container replacement
- Traefik routing with automatic Let's Encrypt certificates

## Usage

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy app
        uses: uncoverthefuture-org/actions/.github/actions/app/ssh-container-deploy@master
        with:
          # Connection
          ssh_host: ${{ secrets.SSH_HOST }}
          ssh_key: ${{ secrets.SSH_KEY }}
          ssh_user: deploy

          # App
          image_name: ghcr.io/my-org/my-app
          version: v1.2.3  # Optional: pin a specific version (overrides image_tag)
          
          # Environment
          env_b64: ${{ secrets.PROD_ENV_B64 }}
          
          # Routing
          domain: api.example.com
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `ssh_host` | Remote host address (IP or DNS) | Yes | |
| `ssh_user` | SSH username | Yes | |
| `ssh_key` | SSH private key | Yes | |
| `version` | Explicit version/tag to deploy. Prioritized over `image_tag`. | No | |
| `image_tag` | Image tag to deploy (e.g. `latest`, `v1.0`). Used if `version` is unset. | No | |
| `image_name` | Container image name (e.g. `ghcr.io/org/app`) | No | Derived from repo |
| `domain` | Domain for Traefik routing | No | |

*(See `action.yml` for the full list of inputs)*
