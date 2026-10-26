# Release Checkpoint

Resolve and validate the exact deployment version once, then pass the output to build and deployment jobs.

```yaml
- uses: actions/checkout@v4
- name: Validate deployment release
  id: release
  uses: uncoverthefuture-org/actions@v1
  with:
    subaction: release-checkpoint
    params_json: |
      {
        "version": "${{ inputs.version }}",
        "prod_branch": "stable"
      }
```

Use `${{ steps.release.outputs.version }}` as both the build version and deployment version. The example uses the package's `v1` channel; changes on the working branch are available there only after release.

## Inputs

| Input | Default | Behavior |
| --- | --- | --- |
| `version` | empty | Highest priority. Accepts `v1.2.3` or `1.2.3`, normalizing the latter to `v1.2.3`. |
| `prod_branch` | `main` or `master` | Optional target override for automatic PR resolution. When set, only that branch is accepted. |
| `verify_tag` | `true` | Fetch the exact tag from origin and require it to reference a commit. Applies to every resolution source. |

These inputs also work when calling the composite action directly. Bash, jq, and Git are required; standard Ubuntu GitHub-hosted runners include them. Checkout the application repository first, with authenticated read access to origin. No PR API permission or GitHub CLI is required.

## Resolution order

1. Explicit `version` input.
2. The tag from a `release: published` event.
3. The exact tag from a non-deletion tag push.
4. A closed, merged PR targeting `prod_branch`: require a `release-please--` branch and extract the version from the **same PR's title**.

Unsupported contexts, ordinary PRs, unmerged PRs, ambiguous titles, and invalid versions fail. Pushes to branches and `workflow_run` require an explicit version passed from the producing workflow; the action never guesses from another merged PR. Development branches are not silently skipped.

Versions support SemVer prereleases such as `v1.2.3-rc.1` without truncation. Leading zeros in numeric identifiers, malformed suffixes, and build metadata (`+...`, incompatible with container image tags) are rejected. The normalized format assumes tags use a `v` prefix.

Tag verification defaults to true. A merged release PR can arrive before Release Please creates its tag. Prefer passing Release Please's `tag_name` output after `release_created`, or resolving from a published release/tag event. If parsing a PR before tag creation is intentional, set `verify_tag: "false"`; the output then represents a proposed version, not a verified deployable release. Tag existence does not prove a registry image is available: deployment must depend on successful image publication.

## Custom production branches

The workflow's trigger must also name the correct target branch:

```yaml
on:
  pull_request:
    types: [closed]
    branches: [stable]
  workflow_dispatch:
    inputs:
      version:
        description: Version tag to deploy
        required: true
```

Keep the job guard for merged release PRs so ordinary merges do not invoke release resolution. Configure Release Please's `target-branch` consistently. If using separate release-triggered workflows, note that events created with the default `GITHUB_TOKEN` generally do not start another workflow; consuming Release Please outputs in the same workflow avoids that dependency.

`prod_branch` configures release PR validation in this checkpoint. It does not change build or deployment environment detection. Pass the resulting `version` output to downstream jobs, and set `env_name: production` on the deployment action when an explicit environment is needed.

## Migration

Replace `subaction: extract-version` with `subaction: release-checkpoint`. The `version` output name stays the same. Resolution now rejects ambiguous contexts and verifies tags for PR-derived versions by default.
