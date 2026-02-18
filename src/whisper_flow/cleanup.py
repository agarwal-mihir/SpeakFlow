from __future__ import annotations

import logging
import re
import subprocess
import time
from dataclasses import dataclass
from typing import Protocol

import requests

from whisper_flow.config import AppConfig
from whisper_flow.language import (
    TranscriptAnalysis,
    decide_output_mode,
    normalize_english,
    normalize_hinglish_roman,
)
from whisper_flow.secret_store import SecretStore

LOGGER = logging.getLogger(__name__)
TOKEN_RE = re.compile(r"[A-Za-z']+")
MULTISPACE_RE = re.compile(r"\s+")
HINDI_ROMAN_KEEP_TOKENS = {
    "bhai",
    "behen",
    "kya",
    "kyun",
    "kaise",
    "haan",
    "nahi",
    "hai",
    "hain",
    "tha",
    "thi",
    "the",
    "acha",
    "accha",
    "yaar",
    "bhaiya",
    "didi",
    "tum",
    "aap",
    "mera",
    "meri",
    "apna",
    "apni",
    "kar",
    "karo",
    "karna",
    "chalo",
    "chal",
    "mat",
    "toh",
    "bas",
    "thik",
    "theek",
    "haanji",
}


@dataclass
class CleanupRequest:
    text: str
    mode: str
    target_script: str


@dataclass
class CleanupResult:
    text: str
    output_mode: str
    used_lmstudio: bool
    rewrite_provider: str | None = None


class TranscriptLike(Protocol):
    raw_text: str
    detected_language: str | None
    confidence: float | None


class SecretStoreLike(Protocol):
    def get_groq_api_key(self) -> str | None:
        ...


def build_system_prompt(output_mode: str) -> str:
    if output_mode == "hinglish_roman":
        return (
            "You are a strict dictation text normalizer.\n"
            "Task: minimally clean text while preserving the original words and meaning.\n"
            "Rules:\n"
            "1) Output Roman Hinglish only.\n"
            "2) Keep Hindi words in Roman script as spoken.\n"
            "3) Never translate Hindi words to English (e.g. bhai->brother, kya->what is forbidden).\n"
            "4) Do not paraphrase, summarize, explain, or add content.\n"
            "5) Only fix spacing, punctuation, casing, and stretched letters.\n"
            "6) Return one plain line only. No quotes, markdown, or preface."
        )
    return (
        "You are a strict dictation text normalizer.\n"
        "Task: minimally clean English text while preserving original words and meaning.\n"
        "Rules:\n"
        "1) Keep the same wording as much as possible.\n"
        "2) Do not paraphrase, summarize, explain, or add content.\n"
        "3) Only fix spacing, punctuation, and casing.\n"
        "4) Return one plain line only. No quotes, markdown, or preface."
    )


def token_budget_for(text: str) -> int:
    return max(40, min(180, (len(text.split()) * 4) + 20))


class LMStudioClient:
    def __init__(
        self,
        base_url: str,
        timeout_ms: int,
        model: str | None = None,
        auto_start: bool = True,
        start_timeout_ms: int = 8000,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = max(timeout_ms, 200) / 1000.0
        self.model = model
        self.auto_start = auto_start
        self.start_timeout = max(start_timeout_ms, 500) / 1000.0
        self._start_attempted = False

    def _list_models(self, quiet: bool = False) -> list[dict] | None:
        try:
            response = requests.get(f"{self.base_url}/models", timeout=self.timeout)
            response.raise_for_status()
            payload = response.json()
            return payload.get("data", [])
        except requests.Timeout:
            if quiet:
                LOGGER.debug("LM Studio model lookup timed out", exc_info=True)
            else:
                LOGGER.warning(
                    "LM Studio model lookup timed out after %.1fs. "
                    "Increase max_cleanup_timeout_ms in config if needed.",
                    self.timeout,
                )
            return None
        except requests.RequestException as exc:
            if quiet:
                LOGGER.debug("LM Studio model lookup failed: %s", exc)
            else:
                LOGGER.warning("Failed to resolve LM Studio model: %s", exc)
            return None
        except Exception:
            if quiet:
                LOGGER.debug("LM Studio model lookup failed due to unexpected error", exc_info=True)
            else:
                LOGGER.warning("Failed to resolve LM Studio model due to unexpected error", exc_info=True)
            return None

    def _ensure_server_running(self) -> bool:
        if not self.auto_start or self._start_attempted:
            return False
        self._start_attempted = True

        LOGGER.warning("LM Studio appears offline. Attempting to launch LM Studio app.")
        try:
            subprocess.run(
                ["open", "-a", "LM Studio"],
                check=False,
                capture_output=True,
                text=True,
                timeout=2.0,
            )
        except Exception:
            LOGGER.warning("Unable to launch LM Studio app automatically", exc_info=True)
            return False

        deadline = time.monotonic() + self.start_timeout
        while time.monotonic() < deadline:
            models = self._list_models(quiet=True)
            if models is not None:
                LOGGER.info("LM Studio became reachable after auto-start")
                return True
            time.sleep(0.35)

        LOGGER.warning("LM Studio did not become reachable within %.1fs", self.start_timeout)
        return False

    def _resolve_model(self) -> str | None:
        if self.model:
            return self.model

        LOGGER.info("LM Studio: resolving model from %s/models", self.base_url)
        models = self._list_models()
        if models is None and self._ensure_server_running():
            models = self._list_models()

        if models is None:
            return None
        if not models:
            LOGGER.warning(
                "LM Studio reachable but no models are loaded. Load a chat model in LM Studio or set lmstudio_model."
            )
            return None

        self.model = models[0]["id"]
        LOGGER.info("LM Studio: using model '%s'", self.model)
        return self.model

    def rewrite(self, text: str, output_mode: str) -> str | None:
        model = self._resolve_model()
        if not model:
            LOGGER.warning("LM Studio model unavailable; skipping cleanup rewrite")
            return None

        payload = {
            "model": model,
            "temperature": 0,
            "max_tokens": token_budget_for(text),
            "messages": [
                {"role": "system", "content": build_system_prompt(output_mode)},
                {"role": "user", "content": text},
            ],
        }

        try:
            LOGGER.info("LM Studio rewrite request started (mode=%s, chars=%d)", output_mode, len(text))
            response = requests.post(
                f"{self.base_url}/chat/completions",
                json=payload,
                timeout=self.timeout,
            )
            response.raise_for_status()
            data = response.json()
            choices = data.get("choices", [])
            if not choices:
                LOGGER.warning("LM Studio returned empty choices")
                return None
            content = choices[0].get("message", {}).get("content", "").strip()
            if content:
                LOGGER.info("LM Studio rewrite applied (chars=%d -> %d)", len(text), len(content))
            return content or None
        except requests.Timeout:
            LOGGER.warning(
                "LM Studio rewrite timed out after %.1fs. "
                "Increase max_cleanup_timeout_ms in config if needed.",
                self.timeout,
            )
            return None
        except requests.RequestException as exc:
            LOGGER.warning("LM Studio rewrite failed: %s", exc)
            return None
        except Exception as exc:
            LOGGER.warning("LM Studio rewrite failed due to unexpected error: %s", exc)
            return None


class GroqClient:
    def __init__(self, base_url: str, timeout_ms: int, model: str, secret_store: SecretStoreLike) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = max(timeout_ms, 200) / 1000.0
        self.model = model
        self.secret_store = secret_store

    def rewrite(self, text: str, output_mode: str) -> str | None:
        api_key = self.secret_store.get_groq_api_key()
        if not api_key:
            LOGGER.warning("Groq API key is missing; skipping Groq cleanup rewrite")
            return None

        payload = {
            "model": self.model,
            "temperature": 0,
            "max_tokens": token_budget_for(text),
            "messages": [
                {"role": "system", "content": build_system_prompt(output_mode)},
                {"role": "user", "content": text},
            ],
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        try:
            LOGGER.info("Groq rewrite request started (mode=%s, chars=%d)", output_mode, len(text))
            response = requests.post(
                f"{self.base_url}/chat/completions",
                json=payload,
                headers=headers,
                timeout=self.timeout,
            )
            response.raise_for_status()
            data = response.json()
            choices = data.get("choices", [])
            if not choices:
                LOGGER.warning("Groq returned empty choices")
                return None
            content = choices[0].get("message", {}).get("content", "").strip()
            if content:
                LOGGER.info("Groq rewrite applied (chars=%d -> %d)", len(text), len(content))
            return content or None
        except requests.Timeout:
            LOGGER.warning(
                "Groq rewrite timed out after %.1fs. Increase max_cleanup_timeout_ms in config if needed.",
                self.timeout,
            )
            return None
        except requests.RequestException as exc:
            LOGGER.warning("Groq rewrite failed: %s", exc)
            return None
        except Exception as exc:
            LOGGER.warning("Groq rewrite failed due to unexpected error: %s", exc)
            return None


class TextCleanup:
    def __init__(self, config: AppConfig, secret_store: SecretStoreLike | None = None) -> None:
        self.config = config
        self.secret_store = secret_store or SecretStore()
        self._lmstudio = LMStudioClient(
            base_url=config.lmstudio_base_url,
            timeout_ms=config.max_cleanup_timeout_ms,
            model=config.lmstudio_model,
            auto_start=config.lmstudio_auto_start,
            start_timeout_ms=config.lmstudio_start_timeout_ms,
        )
        self._groq = GroqClient(
            base_url=config.groq_base_url,
            timeout_ms=config.max_cleanup_timeout_ms,
            model=config.groq_model,
            secret_store=self.secret_store,
        )

    def update_config(self, config: AppConfig) -> None:
        self.config = config
        self._lmstudio = LMStudioClient(
            base_url=config.lmstudio_base_url,
            timeout_ms=config.max_cleanup_timeout_ms,
            model=config.lmstudio_model,
            auto_start=config.lmstudio_auto_start,
            start_timeout_ms=config.lmstudio_start_timeout_ms,
        )
        self._groq = GroqClient(
            base_url=config.groq_base_url,
            timeout_ms=config.max_cleanup_timeout_ms,
            model=config.groq_model,
            secret_store=self.secret_store,
        )

    def clean(self, transcript: TranscriptLike) -> CleanupResult:
        analysis = TranscriptAnalysis(
            raw_text=transcript.raw_text,
            detected_language=transcript.detected_language,
            confidence=transcript.confidence,
        )
        decision = decide_output_mode(self.config.language_mode, analysis)

        request = CleanupRequest(
            text=transcript.raw_text,
            mode=decision.output_mode,
            target_script="latin",
        )

        deterministic = self._deterministic_cleanup(request)
        providers = self._rewrite_provider_order()
        if not providers or not deterministic:
            return CleanupResult(
                text=deterministic,
                output_mode=decision.output_mode,
                used_lmstudio=False,
                rewrite_provider=None,
            )
        LOGGER.info("Cleanup rewrite order: %s", " -> ".join(providers))

        for provider in providers:
            if provider == "groq":
                rewritten = self._groq.rewrite(deterministic, decision.output_mode)
            else:
                rewritten = self._lmstudio.rewrite(deterministic, decision.output_mode)
            rewritten = self._validate_rewrite(
                original=deterministic,
                rewritten=rewritten,
                output_mode=decision.output_mode,
            )
            if rewritten:
                return CleanupResult(
                    text=rewritten,
                    output_mode=decision.output_mode,
                    used_lmstudio=(provider == "lmstudio"),
                    rewrite_provider=provider,
                )
            LOGGER.info("Cleanup provider '%s' unavailable or rejected; trying next fallback", provider)
        return CleanupResult(
            text=deterministic,
            output_mode=decision.output_mode,
            used_lmstudio=False,
            rewrite_provider=None,
        )

    def _rewrite_provider_order(self) -> list[str]:
        if self.config.cleanup_provider == "deterministic":
            return []
        if not self.config.lmstudio_enabled:
            return []

        provider = self.config.cleanup_provider
        if provider in {"priority", "groq", "lmstudio"}:
            return ["groq", "lmstudio"]
        return []

    def _deterministic_cleanup(self, request: CleanupRequest) -> str:
        if request.mode == "hinglish_roman":
            return normalize_hinglish_roman(request.text)
        return normalize_english(request.text)

    def _validate_rewrite(self, original: str, rewritten: str | None, output_mode: str) -> str | None:
        if not rewritten:
            return None

        candidate = rewritten.replace("\n", " ").strip()
        candidate = MULTISPACE_RE.sub(" ", candidate)
        candidate = self._strip_wrapping_quotes(candidate)
        if not candidate:
            return None

        if self._looks_like_meta_response(candidate):
            LOGGER.warning("Cleanup rewrite rejected: meta response detected")
            return None

        original_tokens = self._tokens(original)
        candidate_tokens = self._tokens(candidate)
        if original_tokens and candidate_tokens:
            overlap = self._overlap_ratio(original_tokens, candidate_tokens)
            if overlap < 0.45:
                LOGGER.warning("Cleanup rewrite rejected: low lexical overlap (%.2f)", overlap)
                return None

        original_words = max(1, len(original_tokens))
        candidate_words = len(candidate_tokens)
        if candidate_words > (original_words * 2):
            LOGGER.warning("Cleanup rewrite rejected: output expanded too much")
            return None

        if output_mode == "hinglish_roman" and self._translated_hinglish_terms(original_tokens, candidate_tokens):
            LOGGER.warning("Cleanup rewrite rejected: likely Hinglish-to-English translation")
            return None

        return candidate

    def _tokens(self, text: str) -> list[str]:
        return [t.lower() for t in TOKEN_RE.findall(text)]

    def _overlap_ratio(self, source_tokens: list[str], target_tokens: list[str]) -> float:
        if not source_tokens:
            return 1.0
        source_set = set(source_tokens)
        kept = sum(1 for token in target_tokens if token in source_set)
        return kept / len(source_tokens)

    def _translated_hinglish_terms(self, source_tokens: list[str], target_tokens: list[str]) -> bool:
        source_hinglish = {token for token in source_tokens if token in HINDI_ROMAN_KEEP_TOKENS}
        if not source_hinglish:
            return False
        target_set = set(target_tokens)
        return not any(token in target_set for token in source_hinglish)

    def _looks_like_meta_response(self, text: str) -> bool:
        lowered = text.lower()
        return lowered.startswith(
            (
                "certainly",
                "sure",
                "here's",
                "here is",
                "cleaned",
                "revised",
                "output:",
            )
        )

    def _strip_wrapping_quotes(self, text: str) -> str:
        if len(text) < 2:
            return text
        pairs = {('"', '"'), ("'", "'"), ("“", "”")}
        for left, right in pairs:
            if text.startswith(left) and text.endswith(right):
                return text[1:-1].strip()
        return text
