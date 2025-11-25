# prepare-ubuntu-host

Prepare a fresh Ubuntu host for running containerized apps with Podman:
- Optionally create `podman_user`
- Optionally install Apache, Webmin/Usermin, UFW rules
- Install base tooling (e.g., `jq`, `curl`, CA certificates)

## Inputs (high level)
- SSH: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`, `podman_user?`, `connect_mode?`
- Options: `install_podman?`, `create_podman_user?`, `additional_packages?`, `env_dir_path?`, `install_apache?`, `install_webmin?`, `install_usermin?`, `configure_ufw?`, `ufw_allow_ports?`

### Webmin/Usermin installation (examples)

When `install_webmin` or `install_usermin` is enabled, this action calls the
server-managed `install-webmin.sh` script. That script:

- Detects if `webmin`/`usermin` are already installed and skips reinstallation.
- Ensures the official Webmin APT repository is present:
  - First via the upstream `webmin-setup-repo.sh` helper.
  - If the helper does not register the repo on the host, it falls back to a
    manual APT repo configuration using the documented `jcameron-key.asc`
    keyring and `deb https://download.webmin.com/download/repository sarge contrib`.
- Runs `apt-get update` and `apt-get install webmin [usermin]` once the repo is
  confirmed, so `E: Unable to locate package webmin` should not occur.

**Example: enable Webmin during initial host prep**

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
        "install_webmin": "true",
        "install_usermin": "false"
      }
```

## Example
```yaml
- uses: uncoverthefuture-org/actions@master
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
