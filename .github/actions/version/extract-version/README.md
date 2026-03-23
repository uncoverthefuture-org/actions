# Extract Version (`version/extract-version`)

This action intelligently identifies, extracts, and validates a semantic version string from your workflow context. 

Semantic versioning logic typically demands redundant conditional jobs in your deployment pipelines—this action condenses that boilerplate into a single step.

## Features

- ✨ **Zero configuration** integration with `release-please` PRs.
- ✅ **Automatic validation** to enforce strict semantic version formatting (`v*.*.*`).
- 🏷️ **Git Tag Verification** to assert explicit tags exist before letting deployments proceed.
- 🔁 **Context Awareness** seamlessly falls back between `workflow_dispatch` inputs and Pull Request events.

## Usage Guide

Call this action identically to other uncover aggregator actions. It expects to be called immediately after code checkout, allowing it to verify git tags on the runner's workspace.

### As part of your pipeline

```yaml
jobs:
  get-version:
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' || (github.event_name == 'pull_request' && github.event.pull_request.merged == true)
    outputs:
      version: ${{ steps.extract.outputs.version }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

      - name: Extract Version
        id: extract
        uses: uncoverthefuture-org/actions@v1
        with:
          subaction: extract-version
          params_json: |
            {
              "version": "${{ inputs.version }}"
            }
```

Then simply use `needs.get-version.outputs.version` in downstream deployment jobs.

## Inputs (Via `params_json`)

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `version` | string | **No**  | `""` | Provide an explicit version string. If provided, the action will skip PR detection, ensure formatting validity, and verify a local git tag matches the parameter. |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | The cleanly resolved and validated version string (e.g. `v1.2.3`). Fully ready to be used as your image tag or deployment marker. |

## Execution Logic

1. **Explicit Check:** If the `version` parameter is provided natively (e.g. through a `workflow_dispatch`), the action validates the `^v[0-9]+\.[0-9]+\.[0-9]+$` format string and issues a `git tag -l` lookup. Fails execution if the tag is missing.
2. **Context Fallback Check:** If the input is omitted, it leverages `github.event` variables to see if the workflow was invoked by a closed pull request starting with `release-please--branches--`.
3. parses the title of the Pull Request using Regex matching to securely extract the expected deploy version.
