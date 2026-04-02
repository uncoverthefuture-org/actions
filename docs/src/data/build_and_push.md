# Build and Push

The `build-and-push` subaction compiles Docker or Podman containers directly from your repository and pushes them immediately to secure container registries universally.

## Usage
Include this directly within your jobs array in your workflows securely:

```yaml
- name: Build and Push Image
  uses: uncoverthefuture-org/actions@master
  with:
    subaction: build-and-push
    params_json: |
      {
        "env_name": "production",
        "dockerfile": "Dockerfile",
        "registry": "ghcr.io/uncoverthefuture-org"
      }
    secrets_json: ${{ toJSON(secrets) }}
```

## Parameters (`params_json`)
| Key | Required | Description |
|---|---|---|
| `env_name` | Yes | The environment scope (e.g. `production`, `staging`). |
| `dockerfile` | No | Overrides standard `Dockerfile` location securely. |
| `registry` | Yes | The target remote registry natively mapped! |

## Outputs
- `image_tag`: Provides the SHA hash tag created during the build, which you can pass securely into the `ssh-container-deploy` step subsequently!
