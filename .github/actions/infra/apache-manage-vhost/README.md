# apache-manage-vhost

Create or update an Apache vhost for the Django API. Supports `reverse_proxy` (default) or `mod_wsgi`.

- Domain resolution: either provide `domain`, or provide `base_domain` + `env_name`, using prefixes:
  - prod: `domain_prefix_prod` (default `api`)
  - staging: `domain_prefix_staging` (default `api-staging`)
  - dev: `domain_prefix_dev` (default `api-dev`)

## Inputs
- SSH: `ssh_host`, `ssh_user`, `ssh_key`, `root_ssh_key?`, `ssh_port?`, `ssh_fingerprint?`, `connect_mode='root'`
- Domain: `domain?`, `base_domain?`, `env_name?`, domain prefixes, `require_dns_match?=true`
- Ports: `env_file_path?` (for sourcing), `source_env?=true`, `host_port?`
- Mode: `mode?=reverse_proxy|mod_wsgi`, `wsgi_script_path?`, `server_admin?`

## Example
```yaml
- uses: uncoverthefuture-org/actions@v1
  with:
    subaction: apache-manage-vhost
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_user": "${{ secrets.SSH_USER }}",
        "ssh_key":  "${{ secrets.SSH_KEY }}",
        "env_name": "${{ needs.build.outputs.env_name }}",
        "base_domain": "posteat.co.uk",
        "domain_prefix_prod": "django-api",
        "domain_prefix_staging": "django-api-staging",
        "domain_prefix_dev": "django-api-dev"
      }
```
