# Getting Started with Uncover Actions

This guide walks you through setting up CI/CD for your application using Uncover Actions.

## Prerequisites

Before you start, you'll need:

1. **A GitHub repository** with your application code
2. **A remote server** (Ubuntu 20.04+) where you want to deploy
3. **SSH access** to the remote server
4. **GitHub secrets** configured in your repository

## Step 1: Prepare Your Remote Server

### Option A: Automatic Setup (Recommended)

If you have a fresh Ubuntu server, the actions can set it up automatically:

```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: prepare-ubuntu-host
    params_json: |
      {
        "ssh_host": "your-server.com",
        "ssh_key": "${{ secrets.SSH_KEY }}",
        "install_traefik": true,
        "traefik_email": "admin@example.com"
      }
```

This installs:
- Podman (container runtime)
- Traefik (reverse proxy with Let's Encrypt)
- Required utilities (curl, jq, ca-certificates)

### Option B: Manual Setup

If you prefer to set up manually:

```bash
# SSH into your server with the deploy user configured for GitHub Actions
ssh <ssh_user>@your-server.com

# Install Podman (requires sudo)
sudo apt-get update
sudo apt-get install -y podman

# Install Traefik (optional)
# See: https://doc.traefik.io/traefik/getting-started/install-traefik/
```

## Step 2: Configure GitHub Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

### Required Secrets

- **SSH_HOST**: IP or hostname of your server (e.g., `192.168.1.100` or `deploy.example.com`)
- **SSH_KEY**: Private SSH key for authentication
  - Generate: `ssh-keygen -t ed25519 -f deploy_key`
  - Copy private key content to secret

### Optional Secrets

- **SSH_USER**: Username for SSH (defaults to `root`)
- **SSH_FINGERPRINT**: Server's SSH host key fingerprint (for verification)

### Environment Secrets

For each environment (production, staging, development), create:

- **ENV_B64_PRODUCTION**: Base64-encoded `.env` file for production
- **ENV_B64_STAGING**: Base64-encoded `.env` file for staging
- **ENV_B64_DEVELOPMENT**: Base64-encoded `.env` file for development

**How to create environment secrets:**

```bash
# Create your .env file locally
cat > .env << EOF
DATABASE_URL=postgresql://user:pass@db:5432/myapp
SECRET_KEY=your-secret-key
DEBUG=false
EOF

# Base64 encode it
cat .env | base64

# Copy the output to GitHub secret ENV_B64_PRODUCTION
```

## Step 3: Create Your Workflow

Choose the example that matches your application type:

### Django API

Create `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy Django API

on:
  push:
    branches: [ main, staging, develop ]

permissions:
  contents: read
  packages: write

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - id: build
        uses: uncoverthefuture-org/actions@v1.0.41
        with:
          subaction: build-and-push

      - name: Deploy
        if: ${{ steps.build.outputs.deploy_enabled == 'true' }}
        uses: uncoverthefuture-org/actions@v1.0.41
        with:
          subaction: ssh-django-deploy
          params_json: |
            {
              "ssh_host": "${{ secrets.SSH_HOST }}",
              "ssh_key": "${{ secrets.SSH_KEY }}",
              "base_domain": "example.com",
              "domain_prefix_prod": "api"
            }
```

### Next.js / React

```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-nextjs-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_key": "${{ secrets.SSH_KEY }}",
        "base_domain": "example.com",
        "domain_prefix_prod": "app"
      }
```

### Laravel

```yaml
- uses: uncoverthefuture-org/actions@v1.0.41
  with:
    subaction: ssh-laravel-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SSH_HOST }}",
        "ssh_key": "${{ secrets.SSH_KEY }}",
        "base_domain": "example.com",
        "domain_prefix_prod": "api"
      }
```

## Step 4: Configure Your Dockerfile

Ensure your Dockerfile is in the repository root:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD ["gunicorn", "myapp.wsgi:application", "--bind", "0.0.0.0:8000"]
```

## Step 5: Push and Deploy

```bash
# Commit your workflow file
git add .github/workflows/deploy.yml
git commit -m "Add CI/CD workflow"

# Push to main branch (or staging/develop)
git push origin main
```

The workflow will:
1. Build your Docker image
2. Push it to GitHub Container Registry
3. Deploy it to your server
4. Start the container with Traefik routing

## Step 6: Verify Deployment

### Check the workflow run

1. Go to your GitHub repository
2. Click **Actions**
3. Click the latest workflow run
4. Check the logs for any errors

### Check the remote server

```bash
# SSH into your server
ssh root@your-server.com

# List running containers
podman ps

# Check container logs
podman logs myapp-production

# Check if domain is accessible
curl https://api.example.com
```

## Common Configurations

### With Database

To run a PostgreSQL database container:

```yaml
params_json: |
  {
    "ssh_host": "${{ secrets.SSH_HOST }}",
    "ssh_key": "${{ secrets.SSH_KEY }}",
    "run_db": "true",
    "db_type": "postgres",
    "db_name": "myapp",
    "db_user": "myapp",
    "db_password": "${{ secrets.DB_PASSWORD }}"
  }
```

### With Background Worker

To run a Celery worker:

```yaml
params_json: |
  {
    "ssh_host": "${{ secrets.SSH_HOST }}",
    "ssh_key": "${{ secrets.SSH_KEY }}",
    "run_worker": "true",
    "worker_command": "celery -A myapp worker -l info"
  }
```

### With Scheduler

To run a Celery beat scheduler:

```yaml
params_json: |
  {
    "ssh_host": "${{ secrets.SSH_HOST }}",
    "ssh_key": "${{ secrets.SSH_KEY }}",
    "run_scheduler": "true",
    "scheduler_command": "celery -A myapp beat -l info"
  }
```

### Multiple Environments

To deploy to different servers for different environments:

```yaml
on:
  push:
    branches:
      - main    # Production
      - staging # Staging
      - develop # Development

jobs:
  deploy-prod:
    if: github.ref == 'refs/heads/main'
    # ... deploy to production server

  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    # ... deploy to staging server

  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    # ... deploy to development server
```

## Troubleshooting

### Workflow fails with "SSH connection refused"

**Cause**: SSH credentials are incorrect or server is unreachable.

**Solution**:
1. Verify SSH_HOST is correct
2. Test SSH manually: `ssh -i deploy_key root@SSH_HOST`
3. Check SSH_KEY secret contains the private key (not public key)

### Deployment fails with "Container already exists"

**Cause**: A container with the same name already exists.

**Solution**:
1. SSH into server: `ssh <ssh_user>@your-server.com`
2. Remove old container: `podman rm myapp-production`
3. Re-run the workflow

### Domain not accessible

**Cause**: Traefik not running or DNS not configured.

**Solution**:
1. Check Traefik is running: `podman ps | grep traefik`
2. Validate DNS points to the server:
   - `dig +short api.example.com`
   - `dig +short @ns1.digitalocean.com api.example.com` (authoritative)
   - `dig +short @1.1.1.1 api.example.com` (public)
   - All commands should return the same IP address as your droplet.
3. If DNS records differ, update the offending provider and wait for TTL to expire before re-running Traefik.
4. Check firewall allows ports 80 and 443

### Environment variables not loaded

**Cause**: .env file not created on server.

**Solution**:
1. Verify ENV_B64_PRODUCTION secret is set
2. Check .env file exists: `cat /var/deployments/production/myapp/.env`
3. Check container can read it: `podman exec myapp-production cat /app/.env`

### Migrations fail

**Cause**: Database not running or migrations have errors.

**Solution**:
1. Check database container: `podman ps | grep db`
2. Check database logs: `podman logs db-myapp-production`
3. Test migrations locally: `python manage.py migrate --dry-run`

## Next Steps

1. **Read ARCHITECTURE.md** for deeper understanding of how actions work
2. **Read VARIABLES_REFERENCE.md** for all available parameters
3. **Check action READMEs** for specific action documentation
4. **Explore examples** in `.github/examples/`

## Getting Help

- Check the workflow logs in GitHub Actions
- Review action README files for specific parameters
- Check server logs: `podman logs <container-name>`
- SSH into server and inspect manually

## Best Practices

1. **Use environment secrets**: Store sensitive data in GitHub secrets, not in code
2. **Test locally first**: Use docker-compose to test locally before deploying
3. **Use version tags**: Reference specific action versions (@v1.0.41) for stability
4. **Monitor deployments**: Check logs after each deployment
5. **Backup data**: Ensure database backups before major deployments
6. **Use staging first**: Deploy to staging environment before production
7. **Document your setup**: Keep notes on your deployment configuration

## Security Checklist

- [ ] SSH key is secure (permissions 600)
- [ ] SSH_KEY secret contains private key only
- [ ] SSH_HOST is correct
- [ ] Environment secrets are base64-encoded
- [ ] Database passwords are strong
- [ ] Firewall allows only necessary ports
- [ ] HTTPS is enabled (Traefik with Let's Encrypt)
- [ ] Regular backups are configured
- [ ] Logs are monitored for errors
