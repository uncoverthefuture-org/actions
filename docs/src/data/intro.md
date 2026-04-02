# Uncover Actions

Welcome to **Uncover Actions**, the centralized aggregator for GitHub Actions at Uncover The Future.

This repository (`uncoverthefuture-org/actions`) acts as a primary entry point, routing requests to categorized **sub-actions**. This architectural design keeps workflows unified and extremely maintainable across dozens of microservices.

## How It Works
Instead of importing fifteen different actions, you import exactly one:
```yaml
uses: uncoverthefuture-org/actions@master
with:
  subaction: "build-and-push"
  params_json: '{ "env_name": "production" }'
```
The central dispatcher automatically inspects the `subaction`, categorizes whether it's an `app`, `build`, `infra`, or `common` command, and invokes the underlying runner!

## Features
- **JSON Parameter Payloads**: Reduces input clutter massively by accepting single JSON strings (`params_json`).
- **Secret Isolation**: Protects variable leakage by accepting a secure `secrets_json` input natively.
- **Auto-Restoration**: Safely handles checking-out external code without losing local action contexts.
