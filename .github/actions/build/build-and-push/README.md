# Build and Push Docker Image

A composite GitHub Action that builds a Docker image from your repository and pushes it to a container registry. It serves as the standard build step for CI/CD pipelines.

## Features
- **Docker Build**: Builds image using the repository's `Dockerfile`
- **Registry Auth**: Automatically logs in to the registry (default: `ghcr.io`)
- **Metadata**: Generates image tags and labels (supports custom versions)
- **Environment**: Injects build-time secrets/env via BuildKit secrets
- **Caching**: Uses GitHub Actions cache (`type=gha`) for faster builds

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Build and Push
        uses: uncoverthefuture-org/actions/.github/actions/build/build-and-push@master
        with:
          registry: ghcr.io
          image_name: my-org/my-app
          version: v1.2.3  # Optional: pin specific version tag
          # OR
          image_tag: ${{ github.sha }} # fallback if version not set
          
          secrets_json: ${{ toJSON(secrets) }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `registry` | Docker registry hostname | No | `ghcr.io` |
| `image_name` | Image name (`org/repo`). Defaults to current repo. | No | |
| `version` | Explicit version/tag to publish (overrides `image_tag`) | No | |
| `image_tag` | Tag to publish (e.g. SHA or branch name). Used if `version` unset. | No | |
| `github_token` | Token for registry auth. | No | `github.token` |
| `secrets_json` | JSON string of secrets for build-time env injection | No | |
| `env_name` | Override environment name | No | |

## Outputs

| Output | Description |
|--------|-------------|
| `image_tag` | The tag that was pushed |
| `env_name` | Use environment name |
