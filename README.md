# UActions - Local Container Deployment

A lightweight, local container deployment system powered by Podman and Traefik. Can be used locally or deployed to remote servers via SSH.

## Features

- **Local Domain Routing** - Deploy apps to custom local domains (e.g., `tea.sirdavis99.pc`)
- **Automatic Container Management** - Podman containers with automatic builds
- **Traefik Integration** - Built-in reverse proxy with Let's Encrypt support
- **File Watching** - Auto-deploy when you add new artifacts
- **GitHub PR Creation** - Automatically create PRs with Dockerfile
- **Two Modes**: Local (Podman on localhost) or Remote (SSH to server)
- **Lightweight** - Minimal resource usage, designed for local development and CI/CD

## Installation

### macOS (Recommended - via Homebrew)

```bash
# Install dependencies first
brew install node podman

# Install UActions via Homebrew
brew install uncver/actions/uactions

# Or tap first, then install
brew tap uncver/actions
brew install uactions
```

### npm (All platforms)

```bash
npm install -g @uncver/actions
```

### npx (Quick test without install)

```bash
npx @uncver/actions init --domain yourdomain.pc
```

### yarn

```bash
yarn global add @uncver/actions
```

## Prerequisites

- **macOS** or **Linux**
- **Podman** installed
  - macOS: `brew install podman`
  - Linux: `sudo apt-get install podman`
- **Node.js** 18+

## Quick Start

### 1. Initialize UActions

```bash
uactions init
```

### 2. Create an Artifact

```bash
mkdir ~/uactions/my-app
cat > ~/uactions/my-app/artifact.json << 'EOF'
{
  "version": "1.0.0",
  "name": "My App",
  "source": {
    "url": "https://github.com/user/repo.git"
  },
  "domain": {
    "subdomain": "myapp"
  }
}
EOF
```

### 3. Deploy

```bash
# Deploy locally
uactions deploy my-app

# Or watch for auto-deployment
uactions watch
```

Your app will be available at `http://myapp.<your-domain>.pc`

## Artifact Configuration

```json
{
  "version": "1.0.0",
  "name": "My Application",
  "source": {
    "url": "https://github.com/user/repo.git",
    "ref": "main"
  },
  "domain": {
    "subdomain": "myapp",
    "public": false
  },
  "container": {
    "port": 8080,
    "dockerfile": "./Dockerfile",
    "memory": "512m",
    "cpu": 0.5
  },
  "deploy": {
    "mode": "local",
    "sshHost": "user@server.com",
    "prepareHost": false
  }
}
```

## Remote Server Deployment

Deploy to remote servers via SSH (similar to the original GitHub Action):

```bash
uactions deploy my-app --remote user@server.com
```

Or configure in artifact.json:

```json
{
  "deploy": {
    "mode": "remote",
    "sshHost": "user@server.com",
    "sshKey": "~/.ssh/id_rsa",
    "prepareHost": true
  }
}
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `uactions init` | Initialize UActions |
| `uactions deploy [name]` | Deploy an artifact |
| `uactions watch` | Auto-deploy on file changes |
| `uactions create <name>` | Create new artifact |
| `uactions list` | List deployments/artifacts |
| `uactions status` | Show system status |

## How It Works

1. **File Watcher** monitors `~/uactions/` for `artifact.json` files
2. When detected:
   - Source is pulled to temp directory
   - Docker image is built
   - Container is started with Traefik labels
   - Domain is added to `/etc/hosts`
3. Traefik routes traffic from `subdomain.your-domain.pc` to the container

## License

MIT