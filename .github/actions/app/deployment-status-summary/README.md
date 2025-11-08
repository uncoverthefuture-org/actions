# Deployment Status Summary

Generates a comprehensive deployment status summary for GitHub Actions step summary, including container status, Traefik routing, domain probes, and resource usage.

## Overview

This action orchestrates multiple sub-actions to gather deployment diagnostics and generate a detailed markdown report. The report includes:

- **Container Status**: Podman version, running containers, pods, networks
- **Endpoint Checks**: HTTP probes to domain, host port, and in-container endpoints
- **Traefik Diagnostics**: API reachability, router/service presence, network joins
- **DNS Diagnostics**: Public/authoritative DNS records, IPv4/IPv6 matching
- **Resource Usage**: Podman stats, network listeners, resource snapshots
- **Logs**: Recent container logs and Traefik access logs
- **Optional Probes**: Ephemeral whoami container for path-based routing verification

## Architecture

The action is decomposed into modular sub-actions for focused responsibilities:

```
deployment-status-summary (orchestrator)
├── infra/diagnose-routing (server diagnostics)
├── app/summary/container-status (container inspection)
├── app/summary/resources (Podman stats & system info)
├── app/summary/domain-probe (HTTP endpoint probing)
└── app/summary/traefik-api (Traefik API probing)
```

### Sub-Actions

#### `app/summary/container-status`
Queries container presence, ports, logs, labels, and network configuration.

**Inputs:**
- `ssh_host`, `ssh_user`, `ssh_key`, `ssh_port`
- `container_name` - Container to inspect
- `tail_lines` - Number of log lines to tail (default: 80)

**Outputs:**
- `container_present` - Whether container exists (yes/no)
- `containers_table` - Full `podman ps -a` output
- `recent_logs` - Recent container logs
- `in_container_listeners` - Network listeners inside container
- `app_labels` - Traefik labels on container
- `app_networks` - Networks container is connected to

#### `app/summary/resources`
Collects Podman version, pods, networks, listeners, and resource stats.

**Inputs:**
- `ssh_host`, `ssh_user`, `ssh_key`, `ssh_port`
- `container_name` - Optional, for targeted stats

**Outputs:**
- `podman_version` - Podman version string
- `pods_table` - Podman pods listing
- `networks_table` - Podman networks listing
- `listeners` - Network listeners (ss/netstat output)
- `stats_table` - Podman stats snapshot

#### `app/summary/domain-probe`
Performs HTTP/HTTPS probes from both remote host and GitHub runner.

**Inputs:**
- `ssh_host`, `ssh_user`, `ssh_key`, `ssh_port`
- `domain` - Domain to probe (e.g., example.com)
- `use_https` - Use HTTPS (true) or HTTP (false) (default: true)
- `curl_timeout` - Timeout in seconds (default: 10)

**Outputs:**
- `remote_http_status` - HTTP status from remote host
- `remote_timing` - Response timing from remote host
- `remote_protocol` - HTTP version detected
- `runner_http_status` - HTTP status from GitHub runner
- `runner_timing` - Response timing from runner
- `forwarded_for` - X-Forwarded-For header
- `real_ip` - X-Real-Ip header
- `forwarded` - Forwarded header

#### `app/summary/traefik-api`
Checks Traefik API reachability and router/service presence.

**Inputs:**
- `ssh_host`, `ssh_user`, `ssh_key`, `ssh_port`
- `router_name` - Router name to search for (e.g., my-app-prod)
- `api_timeout` - Timeout in seconds (default: 4)

**Outputs:**
- `api_status` - HTTP status from Traefik API (200, 401, ERR, etc.)
- `router_presence` - Whether router exists (found/not-found/unknown)
- `service_presence` - Whether service exists (found/not-found/unknown)

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `reachable` | Whether SSH host is reachable (from a previous probe) | Yes | - |
| `ssh_host` | Remote SSH host | Yes | - |
| `ssh_user` | SSH username | Yes | - |
| `ssh_key` | SSH private key | Yes | - |
| `ssh_port` | SSH port | No | 22 |
| `app_slug` | Application slug | Yes | - |
| `env_name` | Environment name | Yes | - |
| `container_name` | Container name override | No | (derived) |
| `enable_traefik` | Whether Traefik is enabled | No | true |
| `domain_effective` | Domain used by Traefik | No | - |
| `host_port` | Host port for fallback (non-Traefik) | No | 8080 |
| `container_port` | Container port | No | 8080 |
| `router_name` | Traefik router name to check | No | - |
| `whoami_probe` | Enable ephemeral whoami probe | No | false |
| `traefik_network_name` | Traefik network name | No | traefik-network |
| `run_diagnostics` | Run server diagnostics | No | true |
| `diagnostics_skip_upload` | Skip uploading diagnostics script | No | false |
| `root_ssh_key` | Optional SSH key for root | No | - |
| `traefik_container` | Traefik container name | No | traefik |
| `diagnostics_fail_on_issues` | Fail job if diagnostics detect issues | No | true |
| `diagnostics_attempt_auto_fix` | Attempt automatic remediation | No | true |
| `diagnostics_traefik_email` | Email for Let's Encrypt | No | - |

## Outputs

This action does not produce outputs; it writes directly to `$GITHUB_STEP_SUMMARY`.

## Usage Example

```yaml
- name: Generate deployment status summary
  uses: uncoverthefuture-org/actions/.github/actions/app/deployment-status-summary@main
  with:
    reachable: ${{ steps.probe.outputs.reachable }}
    ssh_host: ${{ secrets.SERVER_HOST }}
    ssh_user: ${{ secrets.SERVER_USER }}
    ssh_key: ${{ secrets.SERVER_SSH_KEY }}
    app_slug: my-app
    env_name: production
    domain_effective: example.com
    enable_traefik: true
    router_name: my-app-prod
    run_diagnostics: true
```

## Behavior

1. **Server Diagnostics** (optional): Runs comprehensive routing diagnostics via `infra/diagnose-routing`
2. **Container Status**: Gathers container info via `app/summary/container-status`
3. **Resource Stats**: Collects system info via `app/summary/resources`
4. **Domain Probe** (if Traefik enabled): Probes domain via `app/summary/domain-probe`
5. **Traefik API** (if router_name provided): Checks API via `app/summary/traefik-api`
6. **Summary Generation**: Orchestrates all data into markdown report
7. **Diagnostics Failure** (if configured): Fails job if critical issues detected

## Notes

- All sub-actions use `continue-on-error: true` to ensure summary generation even if individual probes fail
- SSH key normalization handles both escaped (`\\n`) and literal newlines
- Sanitization removes sensitive data (passwords, tokens, secrets) from output
- DNS diagnostics only run when Traefik is enabled and domain is set
- Whoami probe creates ephemeral container to test path-based routing

## Refactoring Notes

This action was refactored from a monolithic 577-line script into modular sub-actions to:
- Improve maintainability and testability
- Enable reuse of sub-actions in other contexts
- Reduce cognitive load of the main orchestrator
- Separate concerns (container status, resources, probes, API checks)
- Make it easier to add new diagnostic capabilities

All existing behavior and outputs are preserved.
