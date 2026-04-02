# GitHub Actions Workflow Best Practices

## Creating Pull Requests with Up-to-Date Base

When creating a PR that depends on external actions (like `uncoverthefuture-org/actions@master`), always ensure your feature branch is based on the latest main branch:

### Steps Before Creating PR

1. **Always sync with main first:**
   ```bash
   git fetch origin
   git checkout main
   git pull
   git checkout -b your-feature-branch
   ```

2. **If you already have a feature branch, rebase/merge main:**
   ```bash
   git checkout your-feature-branch
   git fetch origin
   git merge origin/main
   ```

### Why This Matters

- External actions like `uses: uncoverthefuture-org/actions@master` may have cached versions in GitHub Actions runners
- If your branch is behind main, you might get stale cached action versions
- This can cause confusing errors like "template is not valid" when the actual file is valid
- Making a small commit to main and pulling ensures you get the latest action code

### Triggering Cache Refresh

If you've pushed updates to the external actions repo and need to force a cache refresh:

1. Make a trivial change to the workflow file in your project (e.g., add a comment)
2. Push the change
3. Re-run the action - GitHub will fetch the latest actions code