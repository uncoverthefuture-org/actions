# Unified Container Deployments

The `uactions` repository standardizes how container applications are shipped across different environments, including direct SSH servers, DigitalOcean droplets (`doctl`), and AWS (`ssm`).

## What can Container Deploy do?

Regardless of the target server, `uactions` synchronizes the deployment process down to identical, reproducible steps:

1. **Host Preparation:** Analyzes the target host environment, creating required application scaffolding and `.env` files dynamically from encrypted GitHub Secrets.
2. **Quadlet Systemd Integration:** Registers containers natively with the Linux system utilizing `podman` Quadlets. 
3. **Smart Image resolution:** Checks target servers and ensures required images are automatically `pull`ed *before* spinning up Quadlet system services.
4. **Resiliency:** Handles transient downtime seamlessly, guaranteeing services stay alive.

## Traefik Traffic Routing

An integral feature of our unified container deployment is **automatic Traefik integration**.

Traefik proxying is now **enabled by default** (`enable_traefik: "true"`) across all deployment configurations.
When a deployment occurs:
- `uactions` provisions a central Traefik container managing ingress.
- Generates automatic Let's Encrypt TLS certificates (ACME) securely.
- Labels your specific application container with Docker labels that Traefik resolves instantly.
- Exposes persistence ports locally for internal server tracking, even if domains aren't specified.
- Traefik health probes are wrapped with timeout controls, ensuring your CI/CD pipeline never hangs indefinitely.

### Portainer Configuration (Suspended)

> **Note:** Portainer installation is currently disabled natively within the `uactions` deployment cycles to harden infrastructure resource limits. Environment variables like `INSTALL_PORTAINER="false"` are hardcoded downstream pending future orchestration requirements.
