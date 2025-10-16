# prepare-ubuntu-host

Prepare a fresh Ubuntu host for running the Django API with Podman:
- Optionally create `podman_user`
- Optionally install Apache, Webmin/Usermin, UFW rules
- Install base tooling (e.g., `jq`, `curl`, CA certificates)

## Inputs (high level)
- SSH: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`, `podman_user?`, `connect_mode?`
- Options: `install_podman?`, `create_podman_user?`, `additional_packages?`, `env_dir_path?`, `install_apache?`, `configure_ufw?`, `ufw_allow_ports?`

## Example
```yaml
- uses: uncoverthefuture-org/actions@v1
  with:
    subaction: prepare-ubuntu-host
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "install_podman": "true",
        "create_podman_user": "false",
        "additional_packages": "jq curl ca-certificates"
      }
```
