#!/usr/bin/env python3
"""Route subaction requests to their dispatcher categories."""
# Example: SA="write-remote-env-file" will select the category whose list includes
# that subaction name so the dispatcher can chain the correct composite action.
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def emit_error(title: str, message: str) -> "NoReturn":  # type: ignore[name-defined]
    print(f"::error title={title}::{message}", file=sys.stderr)
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    # GitHub Actions exports the requested subaction (SA) and optional category override (CAT).
    # We rely on those environment variables instead of CLI args because the composite
    # action wraps this script via bash. No value defaults to empty string after .strip().
    sa = os.environ.get("SA", "").strip()
    cat_override = os.environ.get("CAT", "").strip()
    routes_path_env = os.environ.get("ROUTES_FILE", "").strip()
    routes_path = Path(routes_path_env) if routes_path_env else None

    # Bail out early if the routing table is missing because we cannot make a decision.
    if not routes_path or not routes_path.exists():
        emit_error("Missing routing table", "routes.json not found for route-category action")

    # routes.json contains a mapping of dispatcher category -> [subactions].
    # We load it up front so validation errors surface clearly in the action logs.
    try:
        routes = json.loads(routes_path.read_text("utf-8"))
    except json.JSONDecodeError as exc:  # pragma: no cover - configuration error
        emit_error("Invalid routing table", f"Failed to parse routes.json: {exc}")

    # Defensive schema validation: every value should be a list (of strings).
    if not isinstance(routes, dict) or any(not isinstance(v, list) for v in routes.values()):
        emit_error("Invalid routing table", "routes.json must map categories to lists of subactions")

    valid_categories = set(routes.keys())

    # If CAT is provided, we trust the caller but still confirm it exists to avoid typos.
    if cat_override:
        if cat_override not in valid_categories:
            emit_error("Unsupported category", f"Unsupported category '{cat_override}'")
        category = cat_override
    else:
        # Otherwise we need the SA value so we can search for a matching category.
        if not sa:
            emit_error("Unsupported subaction", "Subaction is required when category is not provided")
        # Iterate through the mapping to locate the category that lists the subaction.
        category = next((cat for cat, subs in routes.items() if sa in subs), None)
        if category is None:
            emit_error("Unsupported subaction", f"Unsupported subaction '{sa}'")

    # Print feedback for GitHub log readability (first consumer is summary step).
    output_line = f"category={category}"
    print(output_line)

    # Also append to GITHUB_OUTPUT so downstream steps can read the category via outputs.
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(output_line + "\n")


if __name__ == "__main__":
    main()
