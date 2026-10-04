#!/usr/bin/env python3
"""Industry pack engine: decide what `pack apply` would do. Pure logic, no network.

  pack.py plan   --pack DIR --live FILE --state FILE --langs bn,en --timezone TZ [--inbox 1,2] [--include-unreviewed] --out FILE
  pack.py state  --plan FILE --state FILE [--failed KEY ...]
  pack.py review PACK_DIR
  pack.py approve PACK_DIR [--key KEY | --all]

`live` is JSON {"canned": [...], "labels": [...], "rules": [...], "inboxes": [...]} read from Chatwoot's API.
`state` remembers what the pack last wrote (hashes only) so a client's own edits are recognised and kept.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pack_data import load  # noqa: E402

CREATE, UPDATE, SAME, KEPT, SKIPPED = "create", "update", "unchanged", "kept", "skipped"
UNPROOFED = "Bangla not yet proofread"


def digest(sig) -> str:
    return hashlib.sha256(json.dumps(sig, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def decide(desired, live, state_hash):
    """create when absent; unchanged when equal; update only if the client has not touched what the pack wrote."""
    if live is None:
        return CREATE, ""
    if live == desired:
        return SAME, ""
    if state_hash is not None and digest(live) == state_hash:
        return UPDATE, ""
    return KEPT, "client edited"


def _reviewed(item_or_block: dict, include: bool) -> bool:
    return include or item_or_block.get("review_required", True) is False


def _action(kind, key, status, reason="", payload=None, sig=None, obj_id=None, inbox=None):
    """`skey` is the key in the state file; it includes the kind because a label and a rule can share a key."""
    return {"kind": kind, "key": key, "skey": f"{kind.split()[0] if inbox is None else 'inbox'}:{key}", "status": status,
            "reason": reason, "payload": payload or {}, "sig": sig, "id": obj_id, "inbox": inbox}


def _decide_action(kind, key, desired, live, state, payload, obj_id=None, inbox=None):
    status, reason = decide(desired, live, state.get(_action(kind, key, SAME, inbox=inbox)["skey"]))
    return _action(kind, key, status, reason, payload, desired, obj_id, inbox)


def plan_canned(pack, langs, include, live, state):
    by_code = {c["short_code"]: c for c in live.get("canned", [])}
    out = []
    for it in pack["canned_responses.yaml"]["items"]:
        for lang in langs:
            code = f"{it['key']}_{lang}"
            if lang == "bn" and not _reviewed(it, include):
                out.append(_action("saved reply", code, SKIPPED, UNPROOFED))
                continue
            cur = by_code.get(code)
            desired = it[lang].strip()
            out.append(_decide_action("saved reply", code, desired, cur["content"].strip() if cur else None, state,
                                      {"short_code": code, "content": it[lang]}, cur and cur["id"]))
    return out


def plan_labels(pack, live, state):
    by_title = {lb["title"]: lb for lb in live.get("labels", [])}
    out = []
    for it in pack["labels.yaml"]["items"]:
        cur = by_title.get(it["key"])
        desired = {"color": it["color"].lower(), "description": it["description"].strip()}
        have = cur and {"color": (cur.get("color") or "").lower(), "description": (cur.get("description") or "").strip()}
        out.append(_decide_action("label", it["key"], desired, have, state,
                                  {"title": it["key"], "description": it["description"], "color": it["color"], "show_on_sidebar": True},
                                  cur and cur["id"]))
    return out


def rule_sig(keywords, label, active=True):
    return {"keywords": sorted(keywords), "labels": [label], "active": active}


def plan_rules(pack, industry, include, live, state):
    by_name = {r["name"]: r for r in live.get("rules", [])}
    out = []
    for it in pack["automations.yaml"]["items"]:
        words = list(it["keywords"]["en"]) + (list(it["keywords"]["bn"]) if _reviewed(it, include) else [])
        name = f"[opskit:{industry}] {it['title']}"
        conditions = [{"attribute_key": "content", "filter_operator": "contains", "values": [w], "query_operator": "OR"} for w in words]
        conditions[-1]["query_operator"] = None
        payload = {"name": name, "description": f"Starter pack '{industry}': tag chats that mention these words.",
                   "event_name": "message_created", "active": True, "conditions": conditions,
                   "actions": [{"action_name": "add_label", "action_params": [it["label"]]}]}
        cur = by_name.get(name)
        have = None
        if cur:
            have = rule_sig([v for c in cur.get("conditions", []) for v in c.get("values", [])],
                            (cur.get("actions") or [{}])[0].get("action_params", [None])[0], cur.get("active", True))
        out.append(_decide_action("rule", it["key"], rule_sig(words, it["label"]), have, state, payload, cur and cur["id"]))
    return out


def hours_sig(enabled, tz, days):
    return {"enabled": bool(enabled), "tz": tz, "days": days}


def _day(d):
    if d.get("closed_all_day") or d.get("closed"):
        return [d.get("day_of_week", d.get("day")), "closed"]
    if d.get("open_all_day"):
        return [d.get("day_of_week", d.get("day")), "all"]
    if "open" in d:
        oh, om = d["open"].split(":")
        ch, cm = d["close"].split(":")
        return [d["day"], int(oh), int(om), int(ch), int(cm)]
    return [d["day_of_week"], d["open_hour"], d["open_minutes"], d["close_hour"], d["close_minutes"]]


def _hours_payload(d):
    oh, om = (d.get("open") or "0:0").split(":")
    ch, cm = (d.get("close") or "0:0").split(":")
    return {"day_of_week": d["day"], "closed_all_day": bool(d.get("closed")), "open_all_day": False,
            "open_hour": int(oh), "open_minutes": int(om), "close_hour": int(ch), "close_minutes": int(cm)}


def _join(block, langs, include):
    """One message holding every allowed language, the client's main language first."""
    parts = [block[lang] for lang in langs if lang == "en" or _reviewed(block, include)]
    return "\n\n".join(parts)


def plan_inbox(pack, langs, include, tz, inbox, state):
    replies, hours = pack["auto_replies.yaml"], pack["business_hours.yaml"]
    iid = inbox["id"]
    name = f"inbox {iid}"
    greeting, ooo = _join(replies["greeting"], langs, include), _join(replies["out_of_office"], langs, include)
    out = []

    def group(slug, label, desired, live, default, payload):
        key = f"{slug}:{iid}"
        status, reason = decide(desired, None if default else live, state.get(f"inbox:{key}"))
        out.append(_action(f"{name} {label}", key, status, reason, payload, desired, inbox=iid))

    if greeting:
        live = {"enabled": bool(inbox.get("greeting_enabled")), "text": inbox.get("greeting_message") or ""}
        group("greeting", "greeting", {"enabled": True, "text": greeting}, live, not live["enabled"] and not live["text"],
              {"greeting_enabled": True, "greeting_message": greeting})
    else:
        out.append(_action(f"{name} greeting", f"greeting:{iid}", SKIPPED, UNPROOFED))
    if ooo:
        live = inbox.get("out_of_office_message") or ""
        group("after_hours", "after-hours message", ooo, live, not live, {"out_of_office_message": ooo})
    else:
        out.append(_action(f"{name} after-hours message", f"after_hours:{iid}", SKIPPED, UNPROOFED))
    days = [_day(d) for d in sorted(hours["days"], key=lambda d: d["day"])]
    live_days = [_day(d) for d in sorted(inbox.get("working_hours") or [], key=lambda d: d["day_of_week"])]
    group("hours", "opening hours", hours_sig(True, tz, days),
          hours_sig(inbox.get("working_hours_enabled"), inbox.get("timezone"), live_days), not inbox.get("working_hours_enabled"),
          {"working_hours_enabled": True, "timezone": tz, "working_hours": [_hours_payload(d) for d in hours["days"]]})
    if replies.get("csat", True):
        enabled = bool(inbox.get("csat_survey_enabled"))
        group("csat", "customer rating (CSAT)", True, enabled, not enabled, {"csat_survey_enabled": True})
    return out


def build_plan(pack, industry, live, state, langs, tz, include, inbox_ids):
    actions = plan_canned(pack, langs, include, live, state) + plan_labels(pack, live, state) + plan_rules(pack, industry, include, live, state)
    for inbox in live.get("inboxes", []):
        if not inbox_ids or inbox["id"] in inbox_ids:
            actions += plan_inbox(pack, langs, include, tz, inbox, state)
    return actions


def summarize(actions):
    counts = {s: sum(1 for a in actions if a["status"] == s) for s in (CREATE, UPDATE, SAME, KEPT, SKIPPED)}
    counts["changes"] = counts[CREATE] + counts[UPDATE]
    return counts


def table(actions) -> str:
    lines = [f"{'WHAT':<10} {'KIND':<28} {'NAME':<34} NOTE"]
    for a in actions:
        lines.append(f"{a['status'].upper():<10} {a['kind']:<28} {a['key']:<34} {a['reason']}".rstrip())
    c = summarize(actions)
    lines.append(f"\n{c[CREATE]} to create, {c[UPDATE]} to update, {c[SAME]} unchanged, {c[KEPT]} kept (client edited), {c[SKIPPED]} skipped")
    return "\n".join(lines)


def cmd_plan(a) -> int:
    pack_dir = Path(a.pack)
    data = load(pack_dir)
    live = json.loads(Path(a.live).read_text())
    state = json.loads(Path(a.state).read_text()) if Path(a.state).exists() else {}
    ids = {int(x) for x in a.inbox.split(",")} if a.inbox else set()
    actions = build_plan(data, pack_dir.name, live, state, a.langs.split(","), a.timezone, a.include_unreviewed, ids)
    Path(a.out).write_text(json.dumps(actions, ensure_ascii=False))
    print(table(actions))
    return 0


def cmd_state(a) -> int:
    path = Path(a.state)
    state = json.loads(path.read_text()) if path.exists() else {}
    for act in json.loads(Path(a.plan).read_text()):
        if act["status"] in (CREATE, UPDATE, SAME) and act["skey"] not in a.failed and act["sig"] is not None:
            state[act["skey"]] = digest(act["sig"])
    path.write_text(json.dumps(state, sort_keys=True, indent=1) + "\n")
    return 0


def cmd_review(a) -> int:
    d = load(Path(a.pack_dir))
    print(f"# Bangla texts to proofread: {Path(a.pack_dir).name}\n")
    print("Mark each OK or write the fix. Only Bangla is reviewed; the English line is the meaning to match.\n")
    for it in d["canned_responses.yaml"]["items"]:
        print(f"## Saved reply `{it['key']}`" + ("" if it.get("review_required", True) else "  (approved)"))
        print(f"- EN: {it['en']}\n- BN: {it['bn']}\n")
    for block in ("greeting", "out_of_office"):
        b = d["auto_replies.yaml"][block]
        print(f"## Automatic message `{block}`" + ("" if b.get("review_required", True) else "  (approved)"))
        print(f"- EN: {b['en']}\n- BN: {b['bn']}\n")
    for it in d["automations.yaml"]["items"]:
        print(f"## Keyword rule `{it['key']}` (tags chats with `{it['label']}`)" + ("" if it.get("review_required", True) else "  (approved)"))
        print(f"- EN words: {', '.join(it['keywords']['en'])}\n- BN words: {', '.join(it['keywords']['bn'])}\n")
    for it in d["kb_starter/faq.yaml"]["items"]:
        print(f"## Starter question `{it['key']}`" + ("" if it.get("review_required", True) else "  (approved)"))
        print(f"- EN: {it['question']['en']}\n- BN: {it['question']['bn']}\n")
    return 0


ITEM = re.compile(r"^\s*(?:- )?key: (\S+)\s*$")
BLOCK = re.compile(r"^(greeting|out_of_office):\s*$")
FLAG = re.compile(r"^(\s*review_required:\s*)true(\s*)$")


def cmd_approve(a) -> int:
    changed = 0
    for name in ("canned_responses.yaml", "auto_replies.yaml", "automations.yaml", "kb_starter/faq.yaml"):
        path = Path(a.pack_dir) / name
        current, lines = None, []
        for line in path.read_text().splitlines(keepends=True):
            m = ITEM.match(line) or BLOCK.match(line)
            if m:
                current = m.group(1)
            f = FLAG.match(line.rstrip("\n"))
            if f and (a.all or current == a.key):
                line = f"{f.group(1)}false{f.group(2)}\n"
                changed += 1
            lines.append(line)
        path.write_text("".join(lines))
    print(f"approved {changed} text(s)")
    return 0 if changed else 1


def main(argv) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("plan")
    s.add_argument("--pack", required=True)
    s.add_argument("--live", required=True)
    s.add_argument("--state", required=True)
    s.add_argument("--langs", required=True)
    s.add_argument("--timezone", required=True)
    s.add_argument("--inbox", default="")
    s.add_argument("--include-unreviewed", action="store_true")
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_plan)
    s = sub.add_parser("state")
    s.add_argument("--plan", required=True)
    s.add_argument("--state", required=True)
    s.add_argument("--failed", nargs="*", default=[])
    s.set_defaults(fn=cmd_state)
    s = sub.add_parser("review")
    s.add_argument("pack_dir")
    s.set_defaults(fn=cmd_review)
    s = sub.add_parser("approve")
    s.add_argument("pack_dir")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--key")
    g.add_argument("--all", action="store_true")
    s.set_defaults(fn=cmd_approve)
    a = p.parse_args(argv[1:])
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
