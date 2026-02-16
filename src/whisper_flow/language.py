from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

OutputMode = Literal["english", "hinglish_roman"]

DEVANAGARI_PATTERN = re.compile(r"[\u0900-\u097F]")
NON_LATIN_PATTERN = re.compile(r"[^\x00-\x7F]")
MULTI_SPACE_PATTERN = re.compile(r"\s+")

DEVANAGARI_INDEPENDENT_VOWELS = {
    "अ": "a",
    "आ": "aa",
    "इ": "i",
    "ई": "ee",
    "उ": "u",
    "ऊ": "oo",
    "ऋ": "ri",
    "ए": "e",
    "ऐ": "ai",
    "ओ": "o",
    "औ": "au",
}

DEVANAGARI_MATRAS = {
    "ा": "aa",
    "ि": "i",
    "ी": "ee",
    "ु": "u",
    "ू": "oo",
    "ृ": "ri",
    "े": "e",
    "ै": "ai",
    "ो": "o",
    "ौ": "au",
}

DEVANAGARI_CONSONANTS = {
    "क": "k",
    "ख": "kh",
    "ग": "g",
    "घ": "gh",
    "ङ": "ng",
    "च": "ch",
    "छ": "chh",
    "ज": "j",
    "झ": "jh",
    "ञ": "ny",
    "ट": "t",
    "ठ": "th",
    "ड": "d",
    "ढ": "dh",
    "ण": "n",
    "त": "t",
    "थ": "th",
    "द": "d",
    "ध": "dh",
    "न": "n",
    "प": "p",
    "फ": "ph",
    "ब": "b",
    "भ": "bh",
    "म": "m",
    "य": "y",
    "र": "r",
    "ल": "l",
    "व": "v",
    "श": "sh",
    "ष": "sh",
    "स": "s",
    "ह": "h",
    "क़": "q",
    "ख़": "kh",
    "ग़": "g",
    "ज़": "z",
    "फ़": "f",
    "ड़": "r",
    "ढ़": "rh",
}

DEVANAGARI_SPECIALS = {
    "ं": "m",
    "ँ": "n",
    "ः": "h",
    "्": "",
}


@dataclass
class LanguageDecision:
    output_mode: OutputMode
    contains_devanagari: bool
    mixed_script_ratio: float


@dataclass
class TranscriptAnalysis:
    raw_text: str
    detected_language: str | None
    confidence: float | None


def contains_devanagari(text: str) -> bool:
    return bool(DEVANAGARI_PATTERN.search(text))


def mixed_script_ratio(text: str) -> float:
    if not text:
        return 0.0
    non_ascii_count = len(NON_LATIN_PATTERN.findall(text))
    return non_ascii_count / max(len(text), 1)


def decide_output_mode(
    language_mode: str,
    analysis: TranscriptAnalysis,
) -> LanguageDecision:
    has_devanagari = contains_devanagari(analysis.raw_text)
    ratio = mixed_script_ratio(analysis.raw_text)

    if language_mode == "english":
        return LanguageDecision("english", has_devanagari, ratio)
    if language_mode == "hinglish_roman":
        return LanguageDecision("hinglish_roman", has_devanagari, ratio)

    if has_devanagari:
        return LanguageDecision("hinglish_roman", has_devanagari, ratio)

    if analysis.detected_language == "hi" and (analysis.confidence or 0.0) >= 0.45:
        return LanguageDecision("hinglish_roman", has_devanagari, ratio)

    if ratio >= 0.07:
        return LanguageDecision("hinglish_roman", has_devanagari, ratio)

    return LanguageDecision("english", has_devanagari, ratio)


def normalize_spaces(text: str) -> str:
    return MULTI_SPACE_PATTERN.sub(" ", text).strip()


def normalize_english(text: str) -> str:
    text = normalize_spaces(text)
    if not text:
        return text

    text = text[0].upper() + text[1:]
    if text[-1] not in ".!?":
        text += "."
    return text


def normalize_hinglish_roman(text: str) -> str:
    if contains_devanagari(text):
        text = transliterate_devanagari(text)
    text = normalize_spaces(text)
    if not text:
        return text

    # Preserve colloquial capitalization; only normalize terminal punctuation.
    if text[-1] not in ".!?":
        text += "."
    return text


def transliterate_devanagari(text: str) -> str:
    output: list[str] = []
    i = 0
    while i < len(text):
        char = text[i]

        if char in DEVANAGARI_INDEPENDENT_VOWELS:
            output.append(DEVANAGARI_INDEPENDENT_VOWELS[char])
            i += 1
            continue

        # Check two-char nukta consonants before single-char consonants
        two_char = text[i:i+2]
        if two_char in DEVANAGARI_CONSONANTS:
            base = DEVANAGARI_CONSONANTS[two_char]
            i += 2
        elif char in DEVANAGARI_CONSONANTS:
            base = DEVANAGARI_CONSONANTS[char]
            i += 1
        else:
            base = None

        if base is not None:
            next_char = text[i] if i < len(text) else ""

            if next_char == "्":
                output.append(base)
                i += 1
                continue

            if next_char in DEVANAGARI_MATRAS:
                output.append(base + DEVANAGARI_MATRAS[next_char])
                i += 1
                continue

            output.append(base + "a")
            continue

        if char in DEVANAGARI_MATRAS:
            output.append(DEVANAGARI_MATRAS[char])
            i += 1
            continue

        if char in DEVANAGARI_SPECIALS:
            output.append(DEVANAGARI_SPECIALS[char])
            i += 1
            continue

        output.append(char)
        i += 1

    return "".join(output)
