# podman-run-service

Run a long-lived container (service) on a remote host via Podman, with optional env file, ports, memory, volumes, and restart policy.

## Inputs
- SSH: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`, `connect_mode?`
- Runtime: `service_name`, `image`, `env_file?`, `command?`, `host_port?`, `container_port?`, `restart_policy?`, `memory_limit?`, `extra_run_args?`, `volumes?`

## Example
```yaml
- uses: uncoverthefuture-org/actions@master
  with:
    subaction: podman-run-service
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "service_name": "django-api-worker",
        "image": "ghcr.io/${{ github.repository }}:${{ needs.build.outputs.image_tag }}",
        "env_file": "/var/deployments/${{ needs.build.outputs.env_name }}/${{ github.event.repository.name }}/.env",
        "command": "python manage.py rqworker default",
        "restart_policy": "unless-stopped",
        "memory_limit": "512m"
      }
```
