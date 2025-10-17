# select-env-secret

Resolves an environment-specific base64 secret using a predictable naming convention.

## Inputs

- `env_name` (**required**): lower-case or mixed-case environment key such as `prod`, `staging`, or `dev`.
- `secret_prefix` (default `ENV_B64_`): prefix that will be concatenated with the upper-cased environment name to create the secret key. Example: `ENV_B64_PROD`.
- `required` (default `false`): when `true`, the action fails if the computed secret is missing or empty.

## Outputs

- `env_b64`: base64 payload retrieved from the secret (empty if not found and `required` is `false`).
- `secret_name`: the exact secret key that was checked.
- `found`: `true` if the secret existed and was non-empty.

## Usage

```yaml
      - name: Select env secret
        id: env
        uses: ./.github/actions/common/select-env-secret
        with:
          env_name: ${{ needs.build.outputs.env_name }}

      - name: Write env file
        uses: uncoverthefuture-org/actions@master
        with:
          subaction: write-remote-env-file
          params_json: |
            {
              "ssh_host": "${{ secrets.SSH_HOST }}",
              "ssh_key":  "${{ secrets.SSH_KEY }}",
              "env_name": "${{ needs.build.outputs.env_name }}",
              "env_b64":  "${{ steps.env.outputs.env_b64 }}"
            }
```

## Secret naming convention

Secrets must follow the pattern `<PREFIX><ENV_NAME>` where `<PREFIX>` defaults to `ENV_B64_` and `<ENV_NAME>` is the uppercase form of the provided environment. For example:

- `ENV_B64_PROD`
- `ENV_B64_STAGING`
- `ENV_B64_DEV`

Override `secret_prefix` if you need a different prefix (e.g., `WORKER_ENV_B64_`).
