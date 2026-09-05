"""Tiny zero-dependency .env loader.

Reads a .env file next to manage.py (backend/.env) and exports KEY=VALUE
pairs into os.environ if not already set. Real environment variables win.
"""
from __future__ import annotations

import os
from pathlib import Path


def load_env(base_dir: Path) -> None:
    env_file = base_dir / ".env"
    if not env_file.exists():
        return
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)
