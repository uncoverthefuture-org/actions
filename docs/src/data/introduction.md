# Introduction to Uactions

Welcome to `@uncover/actions` (`uactions`), the central repository for standardized, reusable GitHub Actions across Uncover's infrastructure!

## What is Uactions?

`uactions` provides a sophisticated workflow dispatch and sub-action execution framework. Rather than duplicating workflow logic across dozens of repositories (like our monolithic apps, APIs, and frontends), repositories simply invoke `uactions` and pass a configuration payload. 

The `uactions` framework dynamically:
1. Evaluates incoming GitHub Action inputs.
2. Identifies the action category (e.g., `app`, `common`).
3. Normalizes and secures JSON payloads using dynamic heredoc delimiters.
4. Validates parameters against strict defaults.
5. Dispatches execution to the requested modular sub-action (such as `ssh-container-deploy`, `doctl-container-deploy`, or `aws-ssm-container-deploy`).

## Core Architecture

Uactions relies on a unified execution pattern:

- **Dispatch controller:** `./.github/actions/<category>/dispatch` serves as the primary router.
- **Normalization:** Automatically merges your custom JSON payloads with strict secure defaults.
- **Probing & Execution:** Wraps risky operations (like Traefik health checks) with timeouts to guarantee pipeline stability.

## Getting Started

To utilize `uactions` in your repository, simply point your workflow to the master branch and provide a `params_json` configuration payload:

```yaml
- name: Deploy Infrastructure
  uses: uncoverthefuture-org/actions@master
  with:
    subaction: ssh-container-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.SERVER_IP }}",
        "ssh_user": "root",
        "ssh_key": "${{ secrets.SSH_PRIVATE_KEY }}",
        "container_port": "8000"
      }
```
