# Quick Start - Uncover Actions

Get up and running in 5 minutes.

## 🚀 30-Second Overview

Uncover Actions is a GitHub Actions collection for deploying applications to remote servers via SSH using Podman containers.

**Supports**: Django, Laravel, Next.js, React, and more.

## ⚡ 5-Minute Setup

### Step 1: Add GitHub Secrets (2 min)

Go to **Settings → Secrets and variables → Actions** and add:

```
SSH_HOST = your-server.com
SSH_KEY = (your private SSH key)
```

### Step 2: Create Workflow (2 min)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [ main, staging, develop ]

permissions:
  contents: read
  packages: write

jobs:
  deploy:
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

### Step 3: Push and Deploy (1 min)

```bash
git add .github/workflows/deploy.yml
git commit -m "Add CI/CD workflow"
git push origin main
```

Done! Check **Actions** tab for deployment status.

## 📋 What You Need

- Ubuntu server (20.04+) with SSH access
- GitHub repository with Dockerfile
- GitHub secrets configured (SSH_HOST, SSH_KEY)

## 🔧 Common Configurations

### With Database

```json
{
  "run_db": "true",
  "db_type": "postgres",
  "db_name": "myapp",
  "db_user": "myapp",
  "db_password": "${{ secrets.DB_PASSWORD }}"
}
```

### With Background Worker

```json
{
  "run_worker": "true",
  "worker_command": "celery -A myapp worker -l info"
}
```

### Different App Type

Change `subaction`:
- Django: `ssh-django-deploy`
- Laravel: `ssh-laravel-deploy`
- Next.js: `ssh-nextjs-deploy`
- React: `ssh-react-deploy`

## 🐛 Troubleshooting

### "SSH connection refused"
- Check SSH_HOST is correct
- Verify SSH_KEY secret contains private key
- Test: `ssh -i deploy_key root@SSH_HOST`

### "Container already exists"
```bash
ssh <ssh_user>@your-server.com
podman rm myapp-production
```

### "Domain not accessible"
- Check DNS alignment:
  - `dig +short api.example.com`
  - `dig +short @ns1.digitalocean.com api.example.com`
  - `dig +short @1.1.1.1 api.example.com`
  - All lookups should resolve to the same IP as your server; if not, update DNS and wait for propagation.
- Check Traefik: `podman ps | grep traefik`
- Check firewall allows ports 80, 443

## 📚 Learn More

- **Full Setup**: [GETTING_STARTED.md](GETTING_STARTED.md)
- **All Parameters**: [VARIABLES_REFERENCE.md](VARIABLES_REFERENCE.md)
- **How It Works**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Find Anything**: [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md)

## 🎯 Next Steps

1. ✅ Add GitHub secrets
2. ✅ Create workflow file
3. ✅ Push to main branch
4. ✅ Check Actions tab
5. 📖 Read [GETTING_STARTED.md](GETTING_STARTED.md) for details

---

**Need help?** Check [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) for navigation.
