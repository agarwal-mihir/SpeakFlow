from whisper_flow.language import (
    TranscriptAnalysis,
    contains_devanagari,
    decide_output_mode,
    mixed_script_ratio,
    normalize_english,
    normalize_hinglish_roman,
    normalize_spaces,
    transliterate_devanagari,
)


def test_auto_chooses_hinglish_for_devanagari() -> None:
    analysis = TranscriptAnalysis(raw_text="भाई क्या हाल है", detected_language="hi", confidence=0.9)
    decision = decide_output_mode("auto", analysis)
    assert decision.output_mode == "hinglish_roman"


def test_auto_chooses_english_for_plain_ascii() -> None:
    analysis = TranscriptAnalysis(raw_text="how are you doing", detected_language="en", confidence=0.88)
    decision = decide_output_mode("auto", analysis)
    assert decision.output_mode == "english"


def test_auto_chooses_hinglish_for_hi_with_confidence_threshold() -> None:
    analysis = TranscriptAnalysis(raw_text="kya haal", detected_language="hi", confidence=0.45)
    decision = decide_output_mode("auto", analysis)
    assert decision.output_mode == "hinglish_roman"


def test_manual_mode_overrides_auto_logic() -> None:
    analysis = TranscriptAnalysis(raw_text="hello", detected_language="en", confidence=0.9)
    assert decide_output_mode("english", analysis).output_mode == "english"
    assert decide_output_mode("hinglish_roman", analysis).output_mode == "hinglish_roman"


def test_normalize_spaces_collapses_runs() -> None:
    assert normalize_spaces("  hello   world  ") == "hello world"


def test_normalize_english_appends_punctuation() -> None:
    assert normalize_english("hello there") == "Hello there."


def test_normalize_hinglish_roman_transliterates_devanagari() -> None:
    text = normalize_hinglish_roman("भाई kya scene hai")
    assert "bh" in text.lower()
    assert text.endswith(".")


def test_transliteration_handles_matra_and_halant() -> None:
    assert transliterate_devanagari("क") == "ka"
    assert transliterate_devanagari("का") == "kaa"
    assert transliterate_devanagari("क्या") == "kyaa"


def test_script_helpers() -> None:
    assert contains_devanagari("hello") is False
    assert contains_devanagari("नमस्ते") is True
    assert mixed_script_ratio("") == 0.0
    assert mixed_script_ratio("abc") == 0.0
    assert mixed_script_ratio("aबc") > 0.0
