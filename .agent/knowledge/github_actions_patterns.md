# GitHub Actions Development Patterns

## GITHUB_OUTPUT Delimiters
**Pattern**: When writing multi-line strings to `$GITHUB_OUTPUT`, NEVER use a static string like `EOF` as the heredoc limit string.
**Reason**: If the user-supplied string contains the identical limit string (e.g., an environment variable carrying an inline script with its own `EOF`), the GitHub Actions parser will terminate the capture prematurely and bleed the rest of the string into the workflow evaluation process, leading to fatal parsing errors like: `After parsing a value an unexpected character was encountered`.

**Correct Implementation**:
Use a dynamically generated hexadecimal delimiter using securely-random utilities like `openssl`.

```bash
# Good implementation
BND=$(openssl rand -hex 16)
{
  echo "json<<$BND"
  printf '%s\n' "$J"
  echo "$BND"
} >> "$GITHUB_OUTPUT"

# Bad implementation (DO NOT USE)
{
  echo "json<<EOF"
  printf '%s\n' "$J"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```
