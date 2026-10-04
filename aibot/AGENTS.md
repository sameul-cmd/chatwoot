# aibot — AI first-reply bot (Python 3.12)

- Follow the `aibot` rules in `.claude/CLAUDE.md` and SPEC 13.
- Pure modules (`lang`, `retrieval`, `policy`, `handoff` rules) have no network I/O; `chatwoot.py` and `llm.py` are the only I/O adapters.
- Commands: `uv run pytest` (or `python -m pytest`), `ruff check .`, `mypy src`. Fake LLM + fake Chatwoot in tests.
- Never log message text; audit goes to the host SQLite only.
