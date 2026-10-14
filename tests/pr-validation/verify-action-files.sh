#!/usr/bin/env bash
# verify-action-files.sh - validates action yaml files for open source PRs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🚀 Running PR Validation Checks scripts..."
echo "Validating syntax and ensuring there are no prohibited usages..."

# Run the local lint-uses logic (simulating what the action does, 
# but directly in the test suite so it fails fast).
REL_FILES=$(find "${REPO_ROOT}" -name "*.yml" -o -name "*.yaml" \
  | grep -v action.yml \
  | xargs grep -lE "^[[:space:]]*uses:[[:space:]]+\./\\.github/actions/" \
  | grep -v "/auto-version.yml$" \
  | grep -v "version/compute-next" \
  | grep -v "version/update-tags" || true)

if [ -n "$REL_FILES" ]; then
  echo "❌ Error: Found relative uses outside of the dispatcher in: $REL_FILES" >&2
  exit 1
fi



# Parse every workflow/action manifest so GitHub does not reject it at runtime.
# GitHub only parses a composite action's manifest when the step referencing it
# runs, so a broken action.yml can otherwise reach master unnoticed.
echo "Validating YAML manifests for duplicate keys and non-printable characters..."

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  python3 -m pip install --quiet --user pyyaml
fi

python3 - "${REPO_ROOT}" <<'PY'
import os
import sys

import yaml

root = os.path.join(sys.argv[1], ".github")
files = sorted(
    os.path.join(dirpath, name)
    for dirpath, _, names in os.walk(root)
    for name in names
    if name.endswith((".yml", ".yaml"))
)


class DuplicateKeyLoader(yaml.SafeLoader):
    pass


def construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(
                f"duplicate key {key!r} (line {key_node.start_mark.line + 1})"
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping
)

failures = []
for path in files:
    with open(path, "rb") as handle:
        raw = handle.read()
    for index, byte in enumerate(raw):
        if byte < 32 and byte not in (9, 10, 13) or byte == 127:
            line = raw.count(b"\n", 0, index) + 1
            failures.append(
                f"{path}:{line}: non-printable byte 0x{byte:02x} in YAML"
            )
            break
    try:
        yaml.load(raw.decode("utf-8"), Loader=DuplicateKeyLoader)
    except Exception as error:  # noqa: BLE001 - report any parse failure verbatim
        failures.append(f"{path}: {str(error).splitlines()[0]}")

if failures:
    print("❌ Error: invalid YAML manifest(s):", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    sys.exit(1)
PY

echo "✅ All PR action files are well-formed and valid!"
exit 0
