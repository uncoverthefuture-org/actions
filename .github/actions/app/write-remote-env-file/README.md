# write-remote-env-file

Write a `.env` file on a remote host via SSH. Uses the same SSH connection and user model as other actions.

- **Derived fallback**: If `env_file_path` is not provided, the dispatcher computes `/var/deployments` from the calling repo name.

## Inputs
- `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`
- `podman_user?` (default `deployer`), `connect_mode?` (`auto|root|user`)
- `env_name` (required)
- `env_file_path?`
- `env_b64?` or `env_content?`

## Example (via root aggregator)
```yaml
- uses: uncoverthefuture-org/actions@master
  with:
    subaction: write-remote-env-file
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "env_name": "staging",
        "env_b64":  "${{ secrets.API_ENV_STAGING_B64 }}"
      }
```
