from pathlib import Path

from aibot.kb import Chunk, load_kb
from aibot.lang import detect, reply_language
from aibot.retrieval import Bm25, retrieve, tokenize

FAQ = """
items:
  - key: delivery_time
    question: {en: "How long does delivery take?", bn: "ডেলিভারিতে কত সময় লাগে?"}
    answer: {en: "Delivery takes two to three days inside Dhaka.", bn: "ঢাকার ভেতরে ডেলিভারিতে দুই থেকে তিন দিন লাগে।"}
    aliases: ["delivery kobe", "kobe pabo"]
  - key: payment
    question: {en: "Which payment methods do you accept?", bn: "কোন পেমেন্ট পদ্ধতি নেন?"}
    answer: {en: "We accept bKash and cash on delivery.", bn: "আমরা বিকাশ ও ক্যাশ অন ডেলিভারি নিই।"}
  - key: unanswered
    question: {en: "What is your return policy?", bn: "রিটার্ন নীতি কী?"}
    answer: {en: "", bn: ""}
"""


def make_kb(tmp_path: Path) -> list[Chunk]:
    (tmp_path / "faq.yaml").write_text(FAQ, encoding="utf-8")
    (tmp_path / "about.md").write_text(
        "# About us\nWe sell handmade bags from Dhaka and open every day.\n", encoding="utf-8"
    )
    return load_kb(tmp_path)


def test_language_detection() -> None:
    assert detect("ডেলিভারি কত দিন লাগে?") == "bn"
    assert detect("How long does delivery take?") == "en"
    assert detect("delivery kobe pabo ami?") == "banglish"
    assert detect("dam koto") == "banglish"
    assert detect("12345 ???") == "unknown"
    assert detect("আমার order কবে আসবে") == "bn"
    assert reply_language("banglish", "bn") == "bn"
    assert reply_language("unknown", "en") == "en"
    assert reply_language("en", "bn") == "en"


def test_tokenize_drops_stop_words_and_cuts_bangla_suffixes() -> None:
    assert tokenize("What is the price of the bag?") == ["price", "bag"]
    assert tokenize("দামের") == ["দাম"]


def test_kb_ignores_entries_without_an_answer(tmp_path: Path) -> None:
    ids = [c.id for c in make_kb(tmp_path)]
    assert "faq:unanswered" not in ids
    assert "faq:delivery_time" in ids and "about#0" in ids


def test_missing_kb_folder_is_empty(tmp_path: Path) -> None:
    assert load_kb(tmp_path / "nope") == []


def test_keyword_search_finds_bangla_english_and_banglish(tmp_path: Path) -> None:
    chunks = make_kb(tmp_path)
    bm25 = Bm25(chunks)
    assert retrieve(chunks, bm25, "How long does delivery take?").chunks[0].id == "faq:delivery_time"
    assert retrieve(chunks, bm25, "ডেলিভারি কত সময় লাগে").chunks[0].id == "faq:delivery_time"
    assert retrieve(chunks, bm25, "delivery kobe pabo").chunks[0].id == "faq:delivery_time"
    assert retrieve(chunks, bm25, "Do you take bkash?").chunks[0].id == "faq:payment"


def test_unrelated_question_finds_nothing(tmp_path: Path) -> None:
    chunks = make_kb(tmp_path)
    result = retrieve(chunks, Bm25(chunks), "What is the capital of France?")
    assert result.chunks == [] and result.mode == "none"


def test_vectors_are_the_fallback_when_keywords_find_nothing(tmp_path: Path) -> None:
    chunks = make_kb(tmp_path)
    vectors = {"faq:delivery_time": [1.0, 0.0], "faq:payment": [0.0, 1.0], "about#0": [0.5, 0.5]}
    result = retrieve(
        chunks, Bm25(chunks), "when will my parcel arrive", query_vec=[0.9, 0.1], vectors=vectors
    )
    assert result.mode == "vector" and result.chunks[0].id == "faq:delivery_time"


def test_keywords_are_the_fallback_without_vectors_or_when_vectors_find_nothing(tmp_path: Path) -> None:
    chunks = make_kb(tmp_path)
    bm25 = Bm25(chunks)
    assert retrieve(chunks, bm25, "payment methods").mode == "bm25"
    far = {"faq:payment": [1.0, 0.0]}
    assert retrieve(chunks, bm25, "payment methods", query_vec=[0.0, 1.0], vectors=far).mode == "bm25"


def test_hybrid_merges_both_and_is_stable(tmp_path: Path) -> None:
    chunks = make_kb(tmp_path)
    vectors = {"faq:delivery_time": [1.0, 0.0], "faq:payment": [0.9, 0.4], "about#0": [0.0, 1.0]}
    kwargs = {"query_vec": [1.0, 0.1], "vectors": vectors}
    first = retrieve(chunks, Bm25(chunks), "delivery payment", **kwargs)  # type: ignore[arg-type]
    again = retrieve(chunks, Bm25(chunks), "delivery payment", **kwargs)  # type: ignore[arg-type]
    assert first.mode == "hybrid"
    assert [c.id for c in first.chunks] == [c.id for c in again.chunks]
    assert {c.id for c in first.chunks} >= {"faq:delivery_time", "faq:payment"}
