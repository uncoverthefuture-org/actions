# Validation Log (SSH User Enforcement)

This log captures manual validation runs that confirm every action executes strictly as the provided `ssh_user` with no `sudo` or `runuser` fallbacks.

## Template Entry

```markdown
### <Date> – <Workflow / Environment>
- Action(s): <e.g., ssh-nextjs-deploy>
- Host: <hostname> (`ssh_user` = <user>)
- Traefik: <enabled|disabled>
- GitHub Run: <https://github.com/...>
- Remote identity output:
  ```
  whoami -> <user>
  id -> uid=<id>(<user>) gid=<id>(<user>) groups=...
  sudo -n true -> <fails/pass>
  ```
- Outcome: <success|failure (with summary)>
- Notes: <any warnings, remediation steps, or observed issues>
```

## Runs

_(Pending – populate once non-root validation hosts are available)_
