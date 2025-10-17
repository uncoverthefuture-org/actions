# cleanup-runner

Frees disk space on GitHub-hosted runners when the available space drops below a threshold. It prunes Docker caches, removes unused volumes, clears apt caches, and deletes temporary files.

## Inputs

- `min_free_gb` (default `10`): Minimum free space in GiB to require before skipping cleanup. Set to `0` to always run the cleanup sequence.

## Usage

```yaml
      - name: Ensure runner has disk space
        uses: ./.github/actions/common/cleanup-runner
        with:
          min_free_gb: '12'  # optional
```

The action prints disk usage before and after the cleanup so you can confirm reclaimed space.
