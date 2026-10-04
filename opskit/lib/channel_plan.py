#!/usr/bin/env python3
"""Print a client's channel to-do list (English + Bangla).
Usage: channel_plan.py CLIENT_YAML PLAN_YAML [--lang en|bn|both] [--for client|owner|all]
Reads channels[] from client.yaml (types: widget email telegram whatsapp facebook instagram api); without any, prints all.
Bangla lines are drafts (review_required) until the owner approves them. No secrets are involved."""
from __future__ import annotations

import sys

import yaml

TYPES = ["widget", "email", "telegram", "whatsapp", "facebook", "instagram", "api"]
WHO = {"client": "CLIENT / ক্লায়েন্ট", "owner": "US / আমরা"}


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    lang, audience = "both", "all"
    rest = argv[3:]
    while rest:
        if rest[0] == "--lang" and len(rest) > 1 and rest[1] in ("en", "bn", "both"):
            lang = rest[1]; rest = rest[2:]
        elif rest[0] == "--for" and len(rest) > 1 and rest[1] in ("client", "owner", "all"):
            audience = rest[1]; rest = rest[2:]
        else:
            print(f"bad option: {rest[0]}", file=sys.stderr)
            return 2
    client = yaml.safe_load(open(argv[1]))
    plan = yaml.safe_load(open(argv[2]))
    chosen = [c["type"] for c in (client.get("channels") or []) if c.get("type") in TYPES]
    note = ""
    if not chosen:
        chosen = TYPES
        note = "(no channels are listed in client.yaml yet: showing every channel)"
    seen: list[str] = []
    for t in ["common"] + chosen:
        if t not in seen:
            seen.append(t)
    subs = {"{domain}": client["domain"], "{client}": client["name"]}

    def sub(text: str) -> str:
        for k, v in subs.items():
            text = text.replace(k, v)
        return text

    print(f"Channel to-do list for {client['name']} ({client['domain']})")
    if note:
        print(note)
    for key in seen:
        ch = plan[key]
        title = ch["title"]
        head = title["en"] if lang == "en" else title["bn"] if lang == "bn" else f"{title['en']} / {title['bn']}"
        print(f"\n== {head} ==")
        n = 0
        for item in ch["items"]:
            if audience != "all" and item["who"] != audience:
                continue
            n += 1
            print(f"  {n}. [{WHO[item['who']]}]")
            if lang in ("en", "both"):
                print(f"     {sub(item['en'])}")
            if lang in ("bn", "both"):
                flag = "  [বাংলা: review needed]" if item.get("review_required", True) else ""
                print(f"     {sub(item['bn'])}{flag}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
