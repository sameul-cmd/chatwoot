#!/usr/bin/env python3
"""Validate a YAML/JSON document against one of opskit's JSON schemas.

Usage: schema_check.py SCHEMA_NAME FILE   (SCHEMA_NAME: client | bot | pack)
Prints one line per problem as `<file>: <field.path>: <message>` and exits 1 if any.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"


def _registry() -> Registry:
    reg: Registry = Registry()
    for p in SCHEMA_DIR.glob("*.schema.json"):
        doc = json.loads(p.read_text())
        reg = reg.with_resource(doc["$id"], Resource.from_contents(doc))
    return reg


def _path(error) -> str:
    parts = [str(p) for p in error.absolute_path]
    return ".".join(parts) if parts else "(root)"


def _message(error) -> str:
    # Spec: shared_accounts is reserved for V2 and must be rejected with a clear "V2" message.
    if error.validator == "enum" and _path(error).endswith("install.mode") and error.instance == "shared_accounts":
        return "install.mode 'shared_accounts' is V2 and not supported yet (use 'dedicated')"
    parts = [str(x) for x in error.absolute_path]
    if error.validator == "const" and len(parts) == 3 and parts[0] == "addons" and parts[2] == "enabled":
        return f"add-on '{parts[1]}' is V2 and not available yet (see docs/ADDONS.md)"
    if error.validator == "const" and parts[:2] == ["alerts", "client_notify"]:
        return "alerts.client_notify.enabled is not available yet: only the owner is notified for now"
    if error.validator == "enum" and parts == ["brand", "mode"]:
        return "brand.mode 'custom' is not available yet: white-label is an owner decision pending (see docs/ADDONS.md)"
    return error.message


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    name, file = argv[1], Path(argv[2])
    schema_path = SCHEMA_DIR / f"{name}.schema.json"
    if not schema_path.exists():
        print(f"unknown schema '{name}'", file=sys.stderr)
        return 2
    try:
        data = yaml.safe_load(file.read_text())
    except (OSError, yaml.YAMLError) as exc:
        print(f"{file}: (root): cannot read document: {exc}")
        return 1
    errors = problems(name, data)
    for path, message in errors:
        print(f"{file}: {path}: {message}")
    return 1 if errors else 0


def problems(name: str, data) -> list[tuple[str, str]]:
    """Return (field path, message) for every way `data` breaks the schema `name`."""
    validator = Draft202012Validator(json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text()), registry=_registry())
    errors = sorted(validator.iter_errors(data), key=lambda e: list(map(str, e.absolute_path)))
    return [(_path(e), _message(e)) for e in errors]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
