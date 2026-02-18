#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$WORKDIR/.venv"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Missing virtualenv at $VENV. Create it first with: python3 -m venv .venv" >&2
  exit 1
fi

source "$VENV/bin/activate"

if ! python -c "import whisper_flow" >/dev/null 2>&1; then
  python -m pip install -e '.[dev]'
fi

exec python -m whisper_flow.main
