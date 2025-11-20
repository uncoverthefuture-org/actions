# AWS SSM Container Deploy

Deploy a generic containerized app to an **AWS EC2 instance** using:

- GitHub OIDC + `aws-actions/configure-aws-credentials` (workload identity)
- AWS Systems Manager **Run Command** (`AWS-RunShellScript`)
- The same **server-managed scripts bundle** used by `ssh-container-deploy` and `doctl-container-deploy`:
  - `scripts/app/start-container-deployment.sh`
  - `scripts/app/run-deployment.sh`
  - `scripts/app/deploy-container.sh`

Once the scripts are on the instance, the deployment behavior (Podman, Traefik, UFW, Webmin, env file handling, probes) is identical.

## Requirements

To use this action safely:

- **GitHub → AWS Workload Identity** is configured:
  - Your repo or org is allowed to assume an IAM role via OIDC.
  - Your workflow job has:

    ```yaml
    permissions:
      id-token: write
      contents: read
    ```

- The IAM role you pass as `aws_role_to_assume` can:
  - Call `ssm:SendCommand`, `ssm:ListCommandInvocations`, `ssm:DescribeInstanceInformation` (read/execute on target instance).
  - Call `s3:PutObject` to the `scripts_bucket`.

- The **EC2 instance**:
  - Has the SSM Agent installed and online (shows as a managed instance).
  - Is referenced by `ssm_target` (usually an instance-id like `i-0123456789abcdef0`).
  - Uses an instance profile/IAM role that can `s3:GetObject` from the same `scripts_bucket`.

## When to use this action

Use `aws-ssm-container-deploy` when:

- Your app runs on AWS EC2.
- You want *no SSH keys* in GitHub Actions – only AWS roles/permissions.
- You want the same deployment semantics as `ssh-container-deploy` / `doctl-container-deploy`.

For DigitalOcean Droplets, see:

- `doctl-container-deploy` (DigitalOcean token + doctl + SSH key)

## Minimal usage via aggregator

Example workflow step using the main `uncoverthefuture-org/actions` aggregator:

```yaml
- name: Deploy to EC2 via AWS SSM
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: aws-ssm-container-deploy
    params_json: |
      {
        "aws_region": "us-east-1",
        "aws_role_to_assume": "arn:aws:iam::123456789012:role/github-oidc-deploy",
        "ssm_target": "i-0123456789abcdef0",

        "scripts_bucket": "my-uactions-scripts-bucket",
        "scripts_prefix": "uactions/scripts",

        "env_name": "production",
        "write_env_file": "true",
        "env_b64": "${{ secrets.PROD_ENV_B64 }}",

        "enable_traefik": "true",
        "base_domain": "${{ secrets.BASE_DOMAIN }}",

        "host_port": "8080",
        "container_port": "3000"
      }
```

**What this does:**

1. Computes defaults for env, image name/tag, and domain.
2. Configures AWS credentials using the provided `aws_role_to_assume` and `aws_region` via OIDC.
3. Bundles `./.github/actions/scripts` → uploads to S3 (`scripts_bucket`/`scripts_prefix`).
4. Uses SSM Run Command to:
   - Download the tarball from S3 to `~/uactions-scripts.tgz` on the instance.
   - Install it into `~/uactions/scripts`.
   - Export all the same deployment env vars used by `ssh-container-deploy`.
   - Run `start-container-deployment.sh`, which in turn runs `run-deployment.sh` and `deploy-container.sh`.

## Key inputs

| Input                 | Required | Description |
|----------------------|----------|-------------|
| `aws_region`         | ✅       | AWS region (e.g. `us-east-1`). |
| `aws_role_to_assume` | ✅       | IAM role ARN GitHub assumes via OIDC. |
| `ssm_target`         | ✅       | EC2 instance-id or SSM-managed instance to deploy to. |
| `scripts_bucket`     | ✅       | S3 bucket where the scripts tarball is uploaded. |
| `scripts_prefix`     | ➖       | Optional key prefix inside the bucket. |
| `env_name`           | ➖       | Logical environment name; auto-detected when omitted. |
| `env_b64` / `env_content` | ➖ | Env payload to materialize on the instance. |
| `image_name` / `image_tag` | ➖ | Container image pieces; default from repo + `<env>-<sha7>`. |
| `enable_traefik`, `domain`/`base_domain` | ➖ | Traefik routing setup, same as other deploy actions. |

The rest of the inputs mirror `ssh-container-deploy` / `doctl-container-deploy` (ports, Traefik flags, dashboard, UFW, Webmin, debug).

## Example: no Traefik, host-port only

```yaml
- name: Deploy dev API to EC2 (no Traefik)
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: aws-ssm-container-deploy
    params_json: |
      {
        "aws_region": "eu-central-1",
        "aws_role_to_assume": "arn:aws:iam::123456789012:role/github-oidc-deploy",
        "ssm_target": "i-0abc1234def567890",
        "scripts_bucket": "my-uactions-scripts-bucket",

        "enable_traefik": "false",
        "env_name": "development",
        "write_env_file": "true",
        "env_b64": "${{ secrets.DEV_ENV_B64 }}",

        "host_port": "8080",
        "container_port": "3000"
      }
```

This deploys your container to the EC2 instance and exposes it on `http://<instance-ip>:8080` without Traefik, while still using the same Podman + UFW + env handling as the other container deploy actions.
