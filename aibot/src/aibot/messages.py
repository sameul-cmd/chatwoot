"""The bot's fixed messages: automation notice, handoff and off-topic, in Bangla and English."""

from __future__ import annotations

from .config import BotConfig
from .models import HandoffReason

# Drafts: the Bangla text is not used on a real client until the owner approves it (messages_bn_approved).
DEFAULTS: dict[str, dict[str, str]] = {
    "disclosure": {
        "en": "Hi! I'm {business}'s automated assistant.",
        "bn": "হ্যালো! আমি {business}-এর স্বয়ংক্রিয় সহকারী।",
    },
    "handoff": {
        "en": "I'm connecting you with a team member who will reply soon. Thank you for waiting.",
        "bn": "আমি আপনাকে আমাদের একজন সদস্যের সাথে যুক্ত করছি, তিনি যত তাড়াতাড়ি সম্ভব উত্তর দেবেন। ধৈর্য ধরার জন্য ধন্যবাদ।",
    },
    "off_topic": {
        "en": "I can only help with questions about {business}. I'm connecting you with a team member.",
        "bn": "আমি শুধু {business} সম্পর্কিত প্রশ্নে সাহায্য করতে পারি। আপনাকে আমাদের একজন সদস্যের সাথে যুক্ত করছি।",
    },
    "upset": {
        "en": "I'm sorry about that. I'm connecting you with a team member right away.",
        "bn": "এ জন্য আমি দুঃখিত। আমি এখনই আপনাকে আমাদের একজন সদস্যের সাথে যুক্ত করছি।",
    },
}
_KEY_FOR_REASON: dict[str, str] = {"off_topic": "off_topic", "no_snippet": "off_topic", "upset": "upset"}


def fixed(key: str, lang: str, cfg: BotConfig) -> str:
    """A fixed message in `lang`. Unapproved default Bangla is replaced by English outside demo mode."""
    override = cfg.messages.get(key, {}).get(lang)
    if override:
        text = override
    elif lang == "bn" and not (cfg.mode == "demo" or cfg.messages_bn_approved):
        text = DEFAULTS[key]["en"]
    else:
        text = DEFAULTS[key][lang]
    return text.format(business=cfg.business_name)


def handoff_message(reason: HandoffReason, lang: str, cfg: BotConfig, first_bot_message: bool) -> str:
    """The handoff text; the automation notice comes first if the bot has not spoken yet."""
    text = fixed(_KEY_FOR_REASON.get(reason, "handoff"), lang, cfg)
    return f"{fixed('disclosure', lang, cfg)}\n\n{text}" if first_bot_message else text


def answer_message(answer: str, lang: str, cfg: BotConfig, first_bot_message: bool) -> str:
    return f"{fixed('disclosure', lang, cfg)}\n\n{answer}" if first_bot_message else answer
