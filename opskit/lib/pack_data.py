#!/usr/bin/env python3
"""Load and validate an industry pack folder (opskit/packs/<industry>/).

Usage: pack_data.py validate PACK_DIR      prints one problem per line, exit 1 if any
Pure data checks only: no network, no Chatwoot.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema_check import problems  # noqa: E402

# file name -> (schema, required)
FILES = {
    "pack.yaml": ("pack_meta", True),
    "canned_responses.yaml": ("pack", True),
    "labels.yaml": ("pack_labels", True),
    "automations.yaml": ("pack_rules", True),
    "business_hours.yaml": ("pack_hours", True),
    "auto_replies.yaml": ("pack_replies", True),
    "kb_starter/faq.yaml": ("pack_kb", True),
}
# Chatwoot variables that exist in saved replies; anything else would be sent to the customer as-is.
VARIABLES = {"contact.name", "contact.first_name", "agent.name", "agent.first_name"}
BANGLA = re.compile("[ঀ-৿]")
DIGITS = re.compile("[0-9০-৯]")
MONEY = re.compile(r"৳|\$|\b(tk|taka|bdt|usd)\b|টাকা", re.I)
BLANK = re.compile(r"\[[^\]]*\]")
VAR = re.compile(r"\{\{\s*([^}]*?)\s*\}\}")


def load(pack_dir: Path) -> dict:
    """Read every pack file; a missing or unreadable file yields None for that name."""
    out: dict = {}
    for name in FILES:
        try:
            out[name] = yaml.safe_load((pack_dir / name).read_text())
        except (OSError, yaml.YAMLError):
            out[name] = None
    return out


def _texts(data: dict) -> list[tuple[str, str, str, bool]]:
    """(where, lang, text, sent_automatically) for every customer-facing text."""
    found = []
    for it in (data["canned_responses.yaml"] or {}).get("items", []):
        for lang in ("bn", "en"):
            found.append((f"canned_responses.yaml:{it['key']}.{lang}", lang, it[lang], False))
    replies = data["auto_replies.yaml"] or {}
    for block in ("greeting", "out_of_office"):
        for lang in ("bn", "en"):
            if block in replies:
                found.append((f"auto_replies.yaml:{block}.{lang}", lang, replies[block][lang], True))
    for it in (data["kb_starter/faq.yaml"] or {}).get("items", []):
        for lang in ("bn", "en"):
            found.append((f"kb_starter/faq.yaml:{it['key']}.{lang}", lang, it["question"][lang], False))
    return found


def _check_text(where: str, lang: str, text: str, auto: bool) -> list[str]:
    bad = []
    if lang == "bn" and not BANGLA.search(text):
        bad.append(f"{where}: Bangla text has no Bangla letters")
    if lang == "en" and BANGLA.search(text):
        bad.append(f"{where}: English text contains Bangla letters")
    if DIGITS.search(text) or MONEY.search(text):
        bad.append(f"{where}: packs must not contain digits, prices or currency (the client's own facts do not belong in a starter pack)")
    if auto and BLANK.search(text):
        bad.append(f"{where}: automatic messages must not contain [blanks]: nobody fills them in before they are sent")
    for var in VAR.findall(text):
        if auto or var not in VARIABLES:
            bad.append(f"{where}: unknown or not allowed variable '{{{{{var}}}}}'")
    return bad


def validate(pack_dir: Path) -> list[str]:
    """Return a list of problem lines (empty = pack is fine)."""
    bad: list[str] = []
    data = load(pack_dir)
    for name, (schema, _) in FILES.items():
        if data[name] is None:
            bad.append(f"{name}: file is missing or not valid YAML")
            continue
        bad += [f"{name}: {path}: {msg}" for path, msg in problems(schema, data[name])]
    if bad:
        return bad
    industry = pack_dir.name
    for name in FILES:
        found = data[name].get("industry")
        if found != industry:
            bad.append(f"{name}: industry '{found}' does not match the folder '{industry}'")
    for name in ("canned_responses.yaml", "labels.yaml", "automations.yaml", "kb_starter/faq.yaml"):
        keys = [it["key"] for it in data[name]["items"]]
        bad += [f"{name}: key '{k}' appears twice" for k in sorted({k for k in keys if keys.count(k) > 1})]
    labels = {it["key"] for it in data["labels.yaml"]["items"]}
    bad += [
        f"automations.yaml: rule '{it['key']}' adds label '{it['label']}' which labels.yaml does not define"
        for it in data["automations.yaml"]["items"]
        if it["label"] not in labels
    ]
    days = sorted(d["day"] for d in data["business_hours.yaml"]["days"])
    if days != list(range(7)):
        bad.append("business_hours.yaml: days must be exactly 0..6 (0 = Sunday), once each")
    for d in data["business_hours.yaml"]["days"]:
        if not d.get("closed") and not (d.get("open") and d.get("close") and d["open"] < d["close"]):
            bad.append(f"business_hours.yaml: day {d['day']} needs closed: true, or open earlier than close")
    for where, lang, text, auto in _texts(data):
        bad += _check_text(where, lang, text, auto)
    for it in data["automations.yaml"]["items"]:
        if any(BANGLA.search(k) for k in it["keywords"]["en"]) or not all(BANGLA.search(k) for k in it["keywords"]["bn"]):
            bad.append(f"automations.yaml: rule '{it['key']}': en keywords must be English and bn keywords Bangla")
    return bad


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "validate":
        print(__doc__, file=sys.stderr)
        return 2
    found = validate(Path(argv[2]))
    for line in found:
        print(line)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
