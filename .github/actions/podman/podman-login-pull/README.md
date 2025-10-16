# podman-login-pull

Log into a container registry and pull an image on a remote host via Podman.

## Inputs
- SSH: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`, `podman_user?`, `connect_mode?`
- Registry: `registry`, `registry_login?=true`, `registry_username?`, `registry_token?`
- Image: `image_name`, `image_tag`

## Example
```yaml
- uses: uncoverthefuture-org/actions@master
  with:
    subaction: podman-login-pull
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "registry": "ghcr.io",
        "registry_login": "true",
        "registry_username": "${{ secrets.GHCR_USERNAME }}",
        "registry_token":   "${{ secrets.GHCR_TOKEN }}",
        "image_name": "${{ github.repository }}",
        "image_tag":  "${{ needs.build.outputs.image_tag }}"
      }
```
