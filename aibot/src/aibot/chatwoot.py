"""The bot's Chatwoot client. Only what the bot token may do (verified live, EXPLORATION_REPORT 5d)."""

from __future__ import annotations

import httpx

from .config import BotConfig


class ChatwootError(Exception):
    """A Chatwoot call failed (the message never contains customer text or tokens)."""


class ChatwootClient:
    def __init__(self, cfg: BotConfig, http: httpx.AsyncClient | None = None) -> None:
        if not (cfg.chatwoot_url and cfg.bot_token):
            raise ChatwootError("AIBOT_CHATWOOT_URL and AIBOT_BOT_TOKEN are required")
        self.base = f"{cfg.chatwoot_url.rstrip('/')}/api/v1/accounts/{cfg.account_id}"
        self.token = cfg.bot_token.get_secret_value()
        self.http = http or httpx.AsyncClient(timeout=httpx.Timeout(15.0))

    async def _post(self, path: str, body: dict[str, object]) -> None:
        try:
            resp = await self.http.post(
                f"{self.base}{path}", json=body, headers={"api-access-token": self.token}
            )
        except httpx.HTTPError as exc:
            raise ChatwootError(f"{type(exc).__name__} calling Chatwoot") from exc
        if resp.status_code >= 300:
            raise ChatwootError(f"Chatwoot refused {path.rsplit('/', 1)[-1]} (HTTP {resp.status_code})")

    async def send_message(self, conversation_id: int, content: str, *, private: bool = False) -> None:
        await self._post(
            f"/conversations/{conversation_id}/messages",
            {"content": content, "message_type": "outgoing", "private": private},
        )

    async def add_labels(self, conversation_id: int, labels: list[str]) -> None:
        await self._post(f"/conversations/{conversation_id}/labels", {"labels": labels})

    async def assign_team(self, conversation_id: int, team_id: int) -> None:
        await self._post(f"/conversations/{conversation_id}/assignments", {"team_id": team_id})

    async def open_conversation(self, conversation_id: int) -> None:
        await self._post(f"/conversations/{conversation_id}/toggle_status", {"status": "open"})
