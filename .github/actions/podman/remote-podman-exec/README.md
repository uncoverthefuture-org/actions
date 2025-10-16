# remote-podman-exec

Run an inline script on a remote host over SSH with a `run_podman` helper function injected. Optionally source an env file before execution.

## Inputs
- `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`
- `podman_user?` (default `deployer`), `connect_mode?` (`auto|root|user`)
- `env_file_path?`, `env_name?`, `source_env?=false`, `fail_if_env_missing?=true`
- `inline_script` (required)

## Notes
- When `source_env=true`, pass `env_file_path` and `env_name` so the action can source `env_file_path + env_name`.

## Example (direct)
```yaml
- uses: uncoverthefuture-org/actions/.github/actions/podman/remote-podman-exec@master
  with:
    ssh_host: ${{ secrets.SSH_HOST }}
    ssh_user: ${{ secrets.SSH_USER }}
    ssh_key:  ${{ secrets.SSH_KEY }}
    podman_user: deployer
    inline_script: |
      run_podman ps -a
```
