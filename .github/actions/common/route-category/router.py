#!/usr/bin/env python3
"""Route subaction requests to their dispatcher categories."""
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
    sa = os.environ.get("SA", "").strip()
    cat_override = os.environ.get("CAT", "").strip()
    routes_path_env = os.environ.get("ROUTES_FILE", "").strip()
    routes_path = Path(routes_path_env) if routes_path_env else None

    if not routes_path or not routes_path.exists():
        emit_error("Missing routing table", "routes.json not found for route-category action")

    try:
        routes = json.loads(routes_path.read_text("utf-8"))
    except json.JSONDecodeError as exc:  # pragma: no cover - configuration error
        emit_error("Invalid routing table", f"Failed to parse routes.json: {exc}")

    if not isinstance(routes, dict) or any(not isinstance(v, list) for v in routes.values()):
        emit_error("Invalid routing table", "routes.json must map categories to lists of subactions")

    valid_categories = set(routes.keys())

    if cat_override:
        if cat_override not in valid_categories:
            emit_error("Unsupported category", f"Unsupported category '{cat_override}'")
        category = cat_override
    else:
        if not sa:
            emit_error("Unsupported subaction", "Subaction is required when category is not provided")
        category = next((cat for cat, subs in routes.items() if sa in subs), None)
        if category is None:
            emit_error("Unsupported subaction", f"Unsupported subaction '{sa}'")

    output_line = f"category={category}"
    print(output_line)

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(output_line + "\n")


if __name__ == "__main__":
    main()
