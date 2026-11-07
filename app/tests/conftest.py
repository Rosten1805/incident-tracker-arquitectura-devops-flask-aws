"""Pytest configuration: makes `app.py` importable from the tests package.

`app/` has no `__init__.py` (it is not meant to be an installable package,
just the app source next to its Dockerfile), so pytest does not add it to
`sys.path` automatically. This adds it explicitly.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
