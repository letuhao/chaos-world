"""Module boundary enforcement. Policy lives in `rules.py`, state in `registry.json`."""

from . import rules
from .enforce import register, run

__all__ = ["register", "rules", "run"]
