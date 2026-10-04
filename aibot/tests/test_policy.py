import pytest

from aibot.config import BotConfig, LLMSettings
from aibot.messages import answer_message, fixed, handoff_message
from aibot.models import LlmAnswer
from aibot.policy import invented_facts, is_upset, post_check, pre_check, wants_human

SOURCES = {"faq:delivery": "Delivery takes two to three days inside Dhaka. The charge is 60 taka."}


def cfg(**kw: object) -> BotConfig:
    return BotConfig(
        llm=LLMSettings(base_url="https://x.example/v1", model="m"),
        mode="demo",
        business_name="Demo Shop",
        **kw,
    )  # type: ignore[arg-type]


def good(**kw: object) -> LlmAnswer:
    base = {"answer": "Delivery takes two to three days.", "confidence": 0.9, "used_ids": ["faq:delivery"]}
    return LlmAnswer(**{**base, **kw})  # type: ignore[arg-type]


@pytest.mark.parametrize(
    "text", ["I want to talk to a human", "please connect me to an agent", "মানুষ চাই", "একজন এজেন্ট দিন"]
)
def test_human_requests_in_both_languages(text: str) -> None:
    assert wants_human(text, cfg())
    assert pre_check(text, 0, cfg()) == "human_request"


def test_english_keywords_match_whole_words_only() -> None:
    assert not wants_human("Do you sell reagent kits?", cfg())  # "agent" inside another word
    assert not wants_human("Where is the humane society?", cfg())


@pytest.mark.parametrize(
    "text", ["This is a complaint", "You cheated me, I want a refund", "আমি অভিযোগ করতে চাই", "এটা প্রতারণা"]
)
def test_upset_words(text: str) -> None:
    assert is_upset(text, cfg())
    assert pre_check(text, 0, cfg()) == "upset"


def test_turn_limit_is_the_fourth_message() -> None:
    assert pre_check("price?", 2, cfg()) is None
    assert pre_check("price?", 3, cfg()) == "max_turns"
    assert pre_check("price?", 1, cfg(max_bot_turns=2)) is None
    assert pre_check("price?", 2, cfg(max_bot_turns=2)) == "max_turns"


def test_human_request_wins_over_turn_limit() -> None:
    assert pre_check("human please", 5, cfg()) == "human_request"


def test_a_good_answer_passes() -> None:
    d = post_check(good(), SOURCES, cfg())
    assert d.action == "answer" and d.used_ids == ("faq:delivery",) and d.reason is None


@pytest.mark.parametrize(
    ("kw", "reason"),
    [
        ({"handoff": True}, "ai_handoff"),
        ({"upset": True}, "upset"),
        ({"confidence": 0.69}, "low_confidence"),
        ({"answer": "  "}, "low_confidence"),
        ({"used_ids": []}, "no_snippet"),
        ({"used_ids": ["faq:invented"]}, "no_snippet"),
        ({"answer": "Delivery takes five days."}, "invented_fact"),
        ({"answer": "The charge is 80 taka."}, "invented_fact"),
        ({"answer": "ডেলিভারি চার্জ ৮০ টাকা।"}, "invented_fact"),
    ],
)
def test_every_gate_hands_off_with_its_reason(kw: dict[str, object], reason: str) -> None:
    d = post_check(good(**kw), SOURCES, cfg())
    assert d.action == "handoff" and d.reason == reason


def test_confidence_exactly_at_the_limit_passes() -> None:
    assert post_check(good(confidence=0.7), SOURCES, cfg()).action == "answer"


def test_fact_guard_accepts_numbers_that_are_in_the_source() -> None:
    assert invented_facts("The charge is 60 taka, two days.", SOURCES["faq:delivery"]) == set()
    assert invented_facts("চার্জ ৬০ টাকা", SOURCES["faq:delivery"]) == set()
    assert invented_facts("It costs 1,200.", "Price: 1200") == set()


def test_disclosure_only_on_the_first_bot_message() -> None:
    c = cfg()
    first = answer_message("Two days.", "en", c, first_bot_message=True)
    assert first.startswith("Hi! I'm Demo Shop's automated assistant.") and first.endswith("Two days.")
    assert answer_message("Two days.", "en", c, first_bot_message=False) == "Two days."


def test_handoff_as_first_message_also_discloses_and_never_claims_to_be_human() -> None:
    c = cfg()
    text = handoff_message("human_request", "en", c, first_bot_message=True)
    assert "automated assistant" in text and "team member" in text
    for key in ("disclosure", "handoff", "off_topic", "upset"):
        for lang in ("en", "bn"):
            assert "human" not in fixed(key, lang, c).casefold().replace("team member", "")


def test_off_topic_and_upset_have_their_own_wording() -> None:
    c = cfg()
    assert "only help with questions about Demo Shop" in handoff_message("off_topic", "en", c, False)
    assert "only help with questions about Demo Shop" in handoff_message("no_snippet", "en", c, False)
    assert "sorry" in handoff_message("upset", "en", c, False)
    assert handoff_message("max_turns", "en", c, False) == fixed("handoff", "en", c)


def test_unapproved_bangla_is_not_used_on_a_real_client() -> None:
    client = BotConfig(
        llm=LLMSettings(base_url="https://x.example/v1", model="m"), mode="client", business_name="Demo Shop"
    )
    assert fixed("handoff", "bn", client) == fixed("handoff", "en", client)
    approved = client.model_copy(update={"messages_bn_approved": True})
    assert fixed("handoff", "bn", approved) != fixed("handoff", "en", approved)
    own = client.model_copy(update={"messages": {"handoff": {"bn": "আমাদের নিজস্ব বার্তা"}}})
    assert fixed("handoff", "bn", own) == "আমাদের নিজস্ব বার্তা"
